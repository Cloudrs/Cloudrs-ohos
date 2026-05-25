use napi_derive::napi;
use std::{fs, sync::{Mutex, OnceLock}};
use cloudreve_api::{
    ApiVersion, CloudreveAPI, DeleteTarget, Error as ApiError, LoginResponse,
    api::v3::models::{
        Aria2CreateRequest, DeleteObjectRequest, MoveObjectRequest,
        CopyObjectRequest, RenameObjectRequest, SourceItems,
        UploadFileRequest, CreateFileRequest,
    },
    api::v4::{
        models::{
            FileType as V4FileType,
            ApiResponse as V4ApiResponse,
            CreateUploadSessionRequest, CreateDownloadRequest, CreateDownloadUrlRequest,
            TaskStatus, TaskType, TaskListResponse,
            CreateShareLinkRequest, PermissionSetting,
            CreateArchiveRequest, ExtractArchiveRequest,
        },
        uri::path_to_uri as v4_path_to_uri,
    },
    cloudreve_api::{SiteConfigValue, FileList},
};
use serde::Serialize;
use serde_json::json;

// ---- v3-compatible DirectoryInfo structs for ArkTS ----

#[derive(Serialize)]
struct ApiObjectInfo {
    id: String,
    name: String,
    path: String,
    thumb: bool,
    size: i64,
    #[serde(rename = "type")]
    object_type: &'static str,
    date: String,
    create_date: String,
    source_enabled: bool,
}

#[derive(Serialize)]
struct ApiPolicy {
    id: String,
    name: String,
    #[serde(rename = "type")]
    policy_type: String,
    max_size: i64,
    file_type: Option<serde_json::Value>,
}

#[derive(Serialize)]
struct ApiDirectoryInfo {
    parent: String,
    objects: Vec<ApiObjectInfo>,
    policy: ApiPolicy,
}

#[derive(Serialize)]
struct ApiUserSetting {
    uid: i64,
    authn: Vec<String>,
    homepage: bool,
    prefer_theme: String,
    themes: String,
    two_factor: bool,
}

#[derive(Serialize)]
struct ApiObjectDetail {
    created_at: String,
    updated_at: String,
    policy: String,
    size: i64,
    child_folder_num: i64,
    child_file_num: i64,
    path: String,
    query_date: String,
}

// Decode percent-encoded URI path and strip the cloudreve URI prefix.
// Handles both "cloudreve://my/..." and "cloudreve://{user}@my/..." formats.
// In the @my format, the path component uses %2F as the path separator,
// e.g. cloudreve://KZHZ@my/%2Fpackages → /packages
fn v4_uri_to_unix(uri: &str) -> String {
    let rest = uri.trim_start_matches("cloudreve://");
    // Find where the path starts: after "@my" or after "my"
    let encoded = if let Some(idx) = rest.find("@my") {
        &rest[idx + 3..] // skip "@my"
    } else if rest.starts_with("my") {
        &rest[2..] // skip "my"
    } else {
        rest
    };
    let src = encoded.as_bytes();
    let mut bytes: Vec<u8> = Vec::with_capacity(src.len());
    let mut i = 0;
    while i < src.len() {
        if src[i] == b'%' && i + 2 < src.len() {
            if let Ok(hex) = std::str::from_utf8(&src[i + 1..i + 3]) {
                if let Ok(b) = u8::from_str_radix(hex, 16) {
                    bytes.push(b);
                    i += 3;
                    continue;
                }
            }
        }
        bytes.push(src[i]);
        i += 1;
    }
    let decoded = String::from_utf8_lossy(&bytes).into_owned();
    // The @my format produces "//path" after decoding (leading / + decoded %2F = //)
    // Collapse leading double-slash to single slash
    if decoded.starts_with("//") {
        decoded[1..].to_string()
    } else if decoded.is_empty() {
        "/".to_string()
    } else {
        decoded
    }
}

fn is_image_file(name: &str) -> bool {
    let ext = name.rsplit('.').next().unwrap_or("").to_lowercase();
    matches!(ext.as_str(), "jpg" | "jpeg" | "png" | "gif" | "webp" | "bmp" | "heic" | "heif" | "tiff" | "tif" | "avif")
}

// Get parent directory from a unix-style path (e.g. "/videos" → "/").
fn unix_parent(full_path: &str) -> String {
    match full_path.rfind('/') {
        None | Some(0) => "/".to_string(),
        Some(idx) => full_path[..idx].to_string(),
    }
}

fn remote_parent(full_path: &str) -> String {
    match full_path.rfind('/') {
        None | Some(0) => "/".to_string(),
        Some(idx) => full_path[..idx].to_string(),
    }
}

async fn ensure_remote_directory(api: &CloudreveAPI, dir: &str) -> Result<(), ApiError> {
    if dir.is_empty() || dir == "/" {
        return Ok(());
    }

    let mut current = String::new();
    for part in dir.split('/').filter(|p| !p.is_empty()) {
        current.push('/');
        current.push_str(part);
        if api.list_files(&current, None, None).await.is_ok() {
            continue;
        }

        api.create_directory(&current).await?;
    }

    Ok(())
}

async fn resolve_upload_policy_id(api: &CloudreveAPI, dir: &str) -> Option<String> {
    match api.list_files(dir, None, None).await {
        Ok(FileList::V4(v4)) => v4.storage_policy.map(|policy| policy.id),
        _ => None,
    }
}

/// Extract a numeric size from a serde_json props object, trying multiple keys and both int/float.
fn extract_size(props: Option<&serde_json::Value>) -> i64 {
    let Some(p) = props else { return 0 };
    for key in &["size", "total", "total_size", "file_size", "length"] {
        if let Some(v) = p.get(key) {
            if let Some(n) = v.as_i64() { return n; }
            if let Some(n) = v.as_f64() { return n as i64; }
        }
    }
    0
}

/// Extract filename from a URL (strip query string and take last path segment).
fn filename_from_url_or_str(s: &str) -> &str {
    let without_query = s.split('?').next().unwrap_or(s);
    without_query.rsplit('/').next().filter(|f| !f.is_empty()).unwrap_or(s)
}

fn decode_v4_prop_path(val: &str) -> String {
    if val.starts_with("cloudreve://") {
        v4_uri_to_unix(val)
    } else {
        val.to_string()
    }
}

fn v4_task_status_to_i32(status: &TaskStatus) -> i32 {
    match status {
        TaskStatus::Queued => 0,
        TaskStatus::Processing | TaskStatus::Suspending => 1,
        TaskStatus::Error => -1,
        TaskStatus::Canceled => 2,
        TaskStatus::Completed => 4,
    }
}

fn v4_task_type_to_i32(task_type: &TaskType) -> i32 {
    match task_type {
        TaskType::RemoteDownload => 2,
        TaskType::Relocate => 4,
        _ => 3,
    }
}

// ---- Global state ----

static CLIENT: OnceLock<Mutex<Option<CloudreveAPI>>> = OnceLock::new();
static V4_REFRESH_TOKEN: OnceLock<Mutex<Option<String>>> = OnceLock::new();

fn state() -> &'static Mutex<Option<CloudreveAPI>> {
    CLIENT.get_or_init(|| Mutex::new(None))
}

fn refresh_state() -> &'static Mutex<Option<String>> {
    V4_REFRESH_TOKEN.get_or_init(|| Mutex::new(None))
}

fn get_client() -> napi::Result<CloudreveAPI> {
    state()
        .lock()
        .unwrap()
        .clone()
        .ok_or_else(|| napi::Error::from_reason("not initialized: call init() first"))
}

fn set_client(api: CloudreveAPI) {
    *state().lock().unwrap() = Some(api);
}

fn get_v4_refresh() -> Option<String> {
    refresh_state().lock().unwrap().clone()
}

fn set_v4_refresh(token: Option<String>) {
    *refresh_state().lock().unwrap() = token;
}

static V4_POLICY_ID: OnceLock<Mutex<Option<String>>> = OnceLock::new();

fn policy_state() -> &'static Mutex<Option<String>> {
    V4_POLICY_ID.get_or_init(|| Mutex::new(None))
}

fn get_v4_policy_id() -> Option<String> {
    policy_state().lock().unwrap().clone()
}

fn set_v4_policy_id(id: Option<String>) {
    *policy_state().lock().unwrap() = id;
}

/// Use the stored refresh_token to get new access/refresh tokens, update client in-place.
async fn do_v4_refresh() -> napi::Result<()> {
    let refresh_tok = get_v4_refresh()
        .ok_or_else(|| napi::Error::from_reason("Unauthorized: no refresh token stored"))?;

    let base_url = get_client()?.base_url().to_string();

    // Use a fresh unauthenticated client so the expired access_token doesn't interfere
    let temp = CloudreveAPI::with_version(&base_url, ApiVersion::V4)
        .map_err(|e| napi::Error::from_reason(e.to_string()))?;

    let new_tok = temp.inner().as_v4()
        .ok_or_else(|| napi::Error::from_reason("Not a v4 client"))?
        .refresh_token(&cloudreve_api::api::v4::models::RefreshTokenRequest {
            refresh_token: &refresh_tok,
        })
        .await
        .map_err(|e| napi::Error::from_reason(format!("Token refresh failed: {}", e)))?;

    log::info!("V4 access token refreshed (len={})", new_tok.access_token.len());

    // Apply new tokens to stored client
    let mut api = get_client()?;
    if let Some(v4) = api.inner_mut().as_v4_mut() {
        v4.set_token(new_tok.access_token);
        v4.set_refresh_token(new_tok.refresh_token.clone());
    }
    set_client(api);
    set_v4_refresh(Some(new_tok.refresh_token));
    Ok(())
}

// ---- Init / session ----

/// Connect to a Cloudreve server, auto-detect v3/v4. Returns "v3" or "v4".
#[napi]
pub async fn init(base_url: String) -> napi::Result<String> {
    let api = CloudreveAPI::new(&base_url)
        .await
        .map_err(|e| napi::Error::from_reason(e.to_string()))?;
    let version = api.api_version().as_str().to_string();
    set_client(api);
    Ok(version)
}

/// Restore a saved session without re-authenticating.
/// For v3: `access_token` is the raw session cookie value (or "cloudreve-session=VALUE").
/// For v4: `access_token` is the JWT access token, `refresh_token` is the refresh token.
#[napi]
pub fn restore_session(base_url: String, access_token: String, refresh_token: String, is_v3: bool) -> napi::Result<()> {
    let version = if is_v3 { ApiVersion::V3 } else { ApiVersion::V4 };
    let mut api = CloudreveAPI::with_version(&base_url, version)
        .map_err(|e| napi::Error::from_reason(e.to_string()))?;
    if is_v3 {
        if let Some(v3) = api.inner_mut().as_v3_mut() {
            let val = access_token
                .strip_prefix("cloudreve-session=")
                .unwrap_or(&access_token)
                .to_string();
            v3.set_session_cookie(val);
        }
    } else {
        api.set_token(&access_token)
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        if !refresh_token.is_empty() {
            if let Some(v4) = api.inner_mut().as_v4_mut() {
                v4.set_refresh_token(refresh_token.clone());
            }
            set_v4_refresh(Some(refresh_token));
        }
    }
    set_client(api);
    Ok(())
}

// ---- Auth ----

fn extract_v4_tokens(response: &LoginResponse) -> (String, String) {
    match response {
        LoginResponse::V4(r) => (r.token.access_token.clone(), r.token.refresh_token.clone()),
        _ => (String::new(), String::new()),
    }
}

/// Login. Returns [userJson, access_token, refresh_token, "v3"/"v4"].
/// When 2FA is required, returns ["2fa_required", "", "", "v3"/"v4"].
#[napi]
pub async fn login(username: String, password: String) -> napi::Result<Vec<String>> {
    let mut api = get_client()?;
    match api.login(&username, &password).await {
        Ok(response) => {
            let v3 = api.inner().is_v3();
            let (access_token, refresh_token) = if v3 {
                (api.get_session_cookie().unwrap_or_default(), String::new())
            } else {
                let tokens = extract_v4_tokens(&response);
                set_v4_refresh(Some(tokens.1.clone()));
                tokens
            };
            let user_json = match &response {
                LoginResponse::V3(r) => serde_json::to_string(&r.user),
                LoginResponse::V4(r) => serde_json::to_string(&r.user),
            }
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
            set_client(api);
            Ok(vec![user_json, access_token, refresh_token, if v3 { "v3" } else { "v4" }.to_string()])
        }
        Err(ApiError::TwoFactorRequired(_)) => {
            let v3 = api.inner().is_v3();
            set_client(api);
            Ok(vec!["2fa_required".to_string(), String::new(), String::new(), if v3 { "v3" } else { "v4" }.to_string()])
        }
        Err(e) => Err(napi::Error::from_reason(e.to_string())),
    }
}

/// Submit 2FA OTP code. Returns [userJson, access_token, refresh_token, "v3"/"v4"].
#[napi(js_name = "login2fa")]
pub async fn login_2fa(code: String) -> napi::Result<Vec<String>> {
    let mut api = get_client()?;
    let response = api
        .login_2fa(&code)
        .await
        .map_err(|e| napi::Error::from_reason(e.to_string()))?;
    let v3 = api.inner().is_v3();
    let (access_token, refresh_token) = if v3 {
        (api.get_session_cookie().unwrap_or_default(), String::new())
    } else {
        let tokens = extract_v4_tokens(&response);
        set_v4_refresh(Some(tokens.1.clone()));
        tokens
    };
    let user_json = match &response {
        LoginResponse::V3(r) => serde_json::to_string(&r.user),
        LoginResponse::V4(r) => serde_json::to_string(&r.user),
    }
    .map_err(|e| napi::Error::from_reason(e.to_string()))?;
    set_client(api);
    Ok(vec![user_json, access_token, refresh_token, if v3 { "v3" } else { "v4" }.to_string()])
}

// ---- Site ----

#[napi]
pub async fn get_site_config() -> napi::Result<String> {
    let api = get_client()?;
    let cfg = api
        .get_site_config(None)
        .await
        .map_err(|e| napi::Error::from_reason(e.to_string()))?;
    match cfg {
        SiteConfigValue::V3(c) => serde_json::to_string(&c),
        SiteConfigValue::V4(c) => serde_json::to_string(&*c),
    }
    .map_err(|e| napi::Error::from_reason(e.to_string()))
}

// ---- User ----

#[napi]
pub async fn get_user_storage() -> napi::Result<String> {
    let api = get_client()?;
    let quota = api
        .get_storage_quota()
        .await
        .map_err(|e| napi::Error::from_reason(e.to_string()))?;
    let j = json!({ "used": quota.used, "total": quota.total, "free": quota.free });
    Ok(j.to_string())
}

#[napi]
pub async fn get_user_setting() -> napi::Result<String> {
    let api = get_client()?;
    if let Some(v3) = api.inner().as_v3() {
        let info = v3
            .get_user_settings()
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        serde_json::to_string(&info).map_err(|e| napi::Error::from_reason(e.to_string()))
    } else {
        let v4 = api.inner().as_v4()
            .ok_or_else(|| napi::Error::from_reason("not a v4 client"))?;
        let settings = v4
            .get_user_setting()
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        let mapped = ApiUserSetting {
            uid: 0,
            authn: settings.passkeys.map(|p| p.iter().map(|k| k.id.clone()).collect()).unwrap_or_default(),
            homepage: false,
            prefer_theme: String::new(),
            themes: String::new(),
            two_factor: settings.two_fa_enabled,
        };
        serde_json::to_string(&mapped).map_err(|e| napi::Error::from_reason(e.to_string()))
    }
}

// ---- Directory / Files ----

#[napi]
pub async fn get_directory(path: String) -> napi::Result<String> {
    let api = get_client()?;
    let result = api.list_files(&path, None, None).await;
    let files = match result {
        Err(ApiError::Unauthorized(_)) => {
            do_v4_refresh().await?;
            get_client()?.list_files(&path, None, None).await
                .map_err(|e| napi::Error::from_reason(e.to_string()))?
        }
        other => other.map_err(|e| napi::Error::from_reason(e.to_string()))?,
    };
    match files {
        FileList::V3(dir) => serde_json::to_string(&dir),
        FileList::V4(v4) => {
            // Cache the policy id for use in upload
            if let Some(policy) = &v4.storage_policy {
                set_v4_policy_id(Some(policy.id.clone()));
            }

            let objects: Vec<ApiObjectInfo> = v4.files.iter().map(|f| {
                let is_dir = matches!(f.r#type, V4FileType::Folder);
                let unix_path = v4_uri_to_unix(&f.path);
                let parent_path = unix_parent(&unix_path);
                ApiObjectInfo {
                    id: unix_path.clone(),   // full path — used by delete/move/copy/rename/download
                    name: f.name.clone(),
                    path: parent_path,       // parent dir — matches V3 convention
                    thumb: !is_dir && is_image_file(&f.name),
                    size: f.size,
                    object_type: if is_dir { "dir" } else { "file" },
                    date: f.updated_at.clone(),
                    create_date: f.created_at.clone(),
                    source_enabled: false,
                }
            }).collect();

            let policy = v4.storage_policy.as_ref()
                .map(|p| ApiPolicy {
                    id: p.id.clone(),
                    name: p.name.clone(),
                    policy_type: p.type_.clone(),
                    max_size: p.max_size as i64,
                    file_type: None,
                })
                .unwrap_or_else(|| ApiPolicy {
                    id: String::new(),
                    name: String::new(),
                    policy_type: String::new(),
                    max_size: 0,
                    file_type: None,
                });

            let parent_unix = v4_uri_to_unix(&v4.parent.path);
            let dir_info = ApiDirectoryInfo { parent: parent_unix, objects, policy };
            serde_json::to_string(&dir_info)
        }
    }
    .map_err(|e| napi::Error::from_reason(e.to_string()))
}

#[napi]
pub async fn get_object_detail(id: String, is_folder: bool) -> napi::Result<String> {
    let api = get_client()?;
    if let Some(v3) = api.inner().as_v3() {
        let prop = v3
            .get_object_property(&id, Some(is_folder), Some(false))
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        serde_json::to_string(&prop).map_err(|e| napi::Error::from_reason(e.to_string()))
    } else {
        let v4 = api.inner().as_v4()
            .ok_or_else(|| napi::Error::from_reason("not a v4 client"))?;
        // id is the unix path (e.g., /videos/movie.mp4)
        let file = v4
            .get_file_info(&id)
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        let detail = ApiObjectDetail {
            created_at: file.created_at.clone(),
            updated_at: file.updated_at.clone(),
            policy: String::new(),
            size: file.size,
            child_folder_num: 0,
            child_file_num: 0,
            path: v4_uri_to_unix(&file.path),
            query_date: file.updated_at.clone(),
        };
        serde_json::to_string(&detail).map_err(|e| napi::Error::from_reason(e.to_string()))
    }
}

// ---- Object operations ----

#[napi]
pub async fn delete_objects(items: Vec<String>, dirs: Vec<String>) -> napi::Result<()> {
    let api = get_client()?;
    if let Some(v3) = api.inner().as_v3() {
        let req = DeleteObjectRequest {
            items: items.iter().map(String::as_str).collect(),
            dirs: dirs.iter().map(String::as_str).collect(),
            force: false,
            unlink: false,
        };
        v3.delete_object(&req)
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))
    } else {
        for path in items.iter().chain(dirs.iter()) {
            api.delete(DeleteTarget::Path(path.clone()))
                .await
                .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        }
        Ok(())
    }
}

#[napi]
pub async fn move_objects(
    items: Vec<String>,
    dirs: Vec<String>,
    src_dir: String,
    dst: String,
) -> napi::Result<()> {
    let api = get_client()?;
    if let Some(v3) = api.inner().as_v3() {
        let src = SourceItems {
            items: items.iter().map(String::as_str).collect(),
            dirs: dirs.iter().map(String::as_str).collect(),
        };
        let req = MoveObjectRequest {
            action: "move",
            src_dir: &src_dir,
            src,
            dst: &dst,
        };
        v3.move_object(&req)
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))
    } else {
        for path in items.iter().chain(dirs.iter()) {
            api.move_file(path, &dst)
                .await
                .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        }
        Ok(())
    }
}

#[napi]
pub async fn copy_objects(
    items: Vec<String>,
    dirs: Vec<String>,
    src_dir: String,
    dst: String,
) -> napi::Result<()> {
    let api = get_client()?;
    if let Some(v3) = api.inner().as_v3() {
        let src = SourceItems {
            items: items.iter().map(String::as_str).collect(),
            dirs: dirs.iter().map(String::as_str).collect(),
        };
        let req = CopyObjectRequest {
            src_dir: &src_dir,
            src,
            dst: &dst,
        };
        v3.copy_object(&req)
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))
    } else {
        for path in items.iter().chain(dirs.iter()) {
            api.copy_file(path, &dst)
                .await
                .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        }
        Ok(())
    }
}

#[napi]
pub async fn rename_object(id: String, new_name: String, is_dir: bool) -> napi::Result<()> {
    let api = get_client()?;
    if let Some(v3) = api.inner().as_v3() {
        let src = if is_dir {
            SourceItems { items: vec![], dirs: vec![&id] }
        } else {
            SourceItems { items: vec![&id], dirs: vec![] }
        };
        let req = RenameObjectRequest {
            action: "rename",
            src,
            new_name: &new_name,
        };
        v3.rename_object(&req)
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))
    } else {
        api.rename(&id, &new_name)
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))
    }
}

#[napi]
pub async fn new_directory(path: String) -> napi::Result<()> {
    let api = get_client()?;
    api.create_directory(&path)
        .await
        .map_err(|e| napi::Error::from_reason(e.to_string()))
}

#[napi]
pub async fn new_file(path: String) -> napi::Result<()> {
    let api = get_client()?;
    if let Some(v3) = api.inner().as_v3() {
        let req = CreateFileRequest { path: &path };
        v3.create_file(&req)
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))
    } else {
        let v4 = api.inner().as_v4()
            .ok_or_else(|| napi::Error::from_reason("not a v4 client"))?;
        // Split path into parent dir and filename for V4 API
        let (parent, name) = match path.rfind('/') {
            None | Some(0) => ("/", path.as_str()),
            Some(idx) => (&path[..idx], &path[idx + 1..]),
        };
        use cloudreve_api::api::v4::models::CreateFileRequest as V4CreateFileRequest;
        let req = V4CreateFileRequest {
            path: parent,
            name,
            content: None,
            overwrite: None,
        };
        v4.create_file(&req)
            .await
            .map(|_| ())
            .map_err(|e| napi::Error::from_reason(e.to_string()))
    }
}

// ---- Download / Upload ----

async fn v4_get_download_url(api: &CloudreveAPI, path: &str) -> napi::Result<String> {
    let v4 = api.inner().as_v4()
        .ok_or_else(|| napi::Error::from_reason("not a v4 client"))?;
    let req = CreateDownloadUrlRequest {
        uris: vec![path],
        download: Some(true),
        redirect: None,
        entity: None,
        use_primary_site_url: None,
        skip_error: None,
        archive: None,
        no_cache: None,
    };
    let resp = v4.create_download_url(&req)
        .await
        .map_err(|e| napi::Error::from_reason(e.to_string()))?;
    resp.urls.into_iter().next()
        .map(|item| item.url)
        .ok_or_else(|| napi::Error::from_reason("no download URL in response"))
}

#[napi]
pub async fn get_download_uri(id: String) -> napi::Result<String> {
    let api = get_client()?;
    if let Some(v3) = api.inner().as_v3() {
        let dl = v3
            .download_file(&id)
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        Ok(dl.url)
    } else {
        let result = v4_get_download_url(&api, &id).await;
        match result {
            Err(_) => {
                if do_v4_refresh().await.is_ok() {
                    let api2 = get_client()?;
                    v4_get_download_url(&api2, &id).await
                } else {
                    result
                }
            }
            ok => ok,
        }
    }
}

/// Returns upload session JSON: { sessionId, chunkSize, expires }
#[napi]
pub async fn get_upload_uri(
    path: String,
    size: u32,
    name: String,
    last_modified: u32,
    mime_type: String,
    _chunk_size: u32,
) -> napi::Result<String> {
    let api = get_client()?;
    if let Some(v3) = api.inner().as_v3() {
        let parent = if let Some(p) = path.rfind('/') {
            if p == 0 { "/" } else { &path[..p] }
        } else {
            "/"
        };
        let dir = v3
            .list_directory(parent)
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        let req = UploadFileRequest {
            path: parent,
            name: &name,
            policy_id: &dir.policy.id,
            size: size as i64,
            last_modified: last_modified as i64,
            mime_type: &mime_type,
        };
        let session = v3
            .upload_file(&req)
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        let j = json!({
            "sessionId": session.session_id,
            "chunkSize": session.chunk_size,
            "expires": session.expires,
        });
        Ok(j.to_string())
    } else {
        let v4 = api.inner().as_v4()
            .ok_or_else(|| napi::Error::from_reason("not a v4 client"))?;
        // Build full file path from parent dir + filename
        let parent = if let Some(p) = path.rfind('/') {
            if p == 0 { "/" } else { &path[..p] }
        } else {
            "/"
        };
        let file_path = if parent == "/" {
            format!("/{}", name)
        } else {
            format!("{}/{}", parent, name)
        };
        let policy_id = get_v4_policy_id().unwrap_or_default();
        let req = CreateUploadSessionRequest {
            uri: &file_path,
            size: size as u64,
            policy_id: &policy_id,
            last_modified: if last_modified > 0 { Some(last_modified as u64) } else { None },
            mime_type: if mime_type.is_empty() { None } else { Some(&mime_type) },
            metadata: None,
            entity_type: None,
        };
        let session = v4
            .create_upload_session(&req)
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        let j = json!({
            "sessionId": session.session_id,
            "chunkSize": session.chunk_size,
            "expires": session.expires,
        });
        Ok(j.to_string())
    }
}

#[napi]
pub async fn upload_local_file(
    local_path: String,
    remote_path: String,
    overwrite: bool,
) -> napi::Result<()> {
    let content = fs::read(&local_path)
        .map_err(|e| napi::Error::from_reason(format!("read local file failed: {}", e)))?;
    let api = get_client()?;
    let parent = remote_parent(&remote_path);
    ensure_remote_directory(&api, &parent)
        .await
        .map_err(|e| napi::Error::from_reason(e.to_string()))?;
    let policy_id = resolve_upload_policy_id(&api, &parent).await;
    if let Some(policy_id) = &policy_id {
        set_v4_policy_id(Some(policy_id.clone()));
    }
    api.upload_file(&remote_path, content, policy_id.as_deref(), overwrite)
        .await
        .map_err(|e| napi::Error::from_reason(e.to_string()))
}

// ---- Aria2 ----

async fn v4_aria2_downloading(api: &CloudreveAPI) -> napi::Result<String> {
    let v4 = api.inner().as_v4()
        .ok_or_else(|| napi::Error::from_reason("not a v4 client"))?;
    let resp: V4ApiResponse<TaskListResponse> = v4.get("/workflow?page_size=100&category=downloading")
        .await
        .map_err(|e| napi::Error::from_reason(e.to_string()))?;
    let task_list = resp.data.ok_or_else(|| napi::Error::from_reason(resp.msg.clone()))?;
    let tasks: Vec<serde_json::Value> = task_list.tasks.iter()
        .filter(|t| matches!(t.status, TaskStatus::Queued | TaskStatus::Processing | TaskStatus::Suspending))
        .map(|t| {
            let props = t.summary.as_ref().map(|s| &s.props);
            let dl = props.and_then(|p| p.get("download"));
            let raw_name = dl
                .and_then(|d| d.get("name").and_then(|v| v.as_str()))
                .or_else(|| props.and_then(|p| p.get("src_str").and_then(|v| v.as_str())))
                .or_else(|| props.and_then(|p| p.get("url_str").and_then(|v| v.as_str())))
                .or_else(|| props.and_then(|p| p.get("src").and_then(|v| v.as_str())))
                .or_else(|| props.and_then(|p| p.get("url").and_then(|v| v.as_str())))
                .unwrap_or(&t.id);
            let name = filename_from_url_or_str(raw_name).to_string();
            let total = dl
                .and_then(|d| d.get("total").and_then(|v| v.as_i64()))
                .unwrap_or_else(|| extract_size(props));
            let downloaded = dl
                .and_then(|d| d.get("downloaded").and_then(|v| v.as_i64()))
                .unwrap_or(0);
            let speed = dl
                .and_then(|d| d.get("download_speed").and_then(|v| v.as_i64()))
                .unwrap_or(0);
            let dst = props
                .and_then(|p| p.get("dst").and_then(|v| v.as_str())
                    .or_else(|| p.get("dst_str").and_then(|v| v.as_str()))
                    .or_else(|| p.get("path").and_then(|v| v.as_str())))
                .map(decode_v4_prop_path)
                .unwrap_or_default();
            json!({
                "name": name,
                "status": v4_task_status_to_i32(&t.status),
                "total": total,
                "downloaded": downloaded,
                "speed": speed,
                "interval": 5,
                "dst": dst,
                "node": t.node.as_ref().map(|n| n.name.as_str()).unwrap_or(""),
                "update": t.updated_at,
                "info": {
                    "gid": t.id,
                    "status": "active",
                    "totalLength": total.to_string(),
                    "completedLength": downloaded.to_string(),
                    "downloadSpeed": speed.to_string(),
                    "errorMessage": t.error.as_deref().unwrap_or(""),
                    "files": []
                }
            })
        })
        .collect();
    serde_json::to_string(&tasks).map_err(|e| napi::Error::from_reason(e.to_string()))
}

#[napi]
pub async fn aria2_downloading() -> napi::Result<String> {
    let api = get_client()?;
    if let Some(v3) = api.inner().as_v3() {
        let tasks = v3
            .list_downloading()
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        serde_json::to_string(&tasks).map_err(|e| napi::Error::from_reason(e.to_string()))
    } else {
        let result = v4_aria2_downloading(&api).await;
        match result {
            Err(_) => {
                if do_v4_refresh().await.is_ok() {
                    let api2 = get_client()?;
                    v4_aria2_downloading(&api2).await
                } else {
                    result
                }
            }
            ok => ok,
        }
    }
}

async fn v4_aria2_finished(api: &CloudreveAPI) -> napi::Result<String> {
    let v4 = api.inner().as_v4()
        .ok_or_else(|| napi::Error::from_reason("not a v4 client"))?;
        let resp: V4ApiResponse<TaskListResponse> = v4.get("/workflow?page_size=100&category=downloaded")
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        let task_list = resp.data.ok_or_else(|| napi::Error::from_reason(resp.msg.clone()))?;
        let tasks: Vec<serde_json::Value> = task_list.tasks.iter()
            .filter(|t| matches!(t.status, TaskStatus::Completed | TaskStatus::Error | TaskStatus::Canceled))
            .map(|t| {
                let props = t.summary.as_ref().map(|s| &s.props);
                let dl = props.and_then(|p| p.get("download"));
                let raw_name = dl
                    .and_then(|d| d.get("name").and_then(|v| v.as_str()))
                    .or_else(|| props.and_then(|p| p.get("src_str").and_then(|v| v.as_str())))
                    .or_else(|| props.and_then(|p| p.get("url_str").and_then(|v| v.as_str())))
                    .or_else(|| props.and_then(|p| p.get("src").and_then(|v| v.as_str())))
                    .or_else(|| props.and_then(|p| p.get("url").and_then(|v| v.as_str())))
                    .unwrap_or(&t.id);
                let name = filename_from_url_or_str(raw_name).to_string();
                let total = dl
                    .and_then(|d| d.get("total").and_then(|v| v.as_i64()))
                    .unwrap_or_else(|| extract_size(props));
                let dst = props
                    .and_then(|p| p.get("dst").and_then(|v| v.as_str())
                        .or_else(|| p.get("dst_str").and_then(|v| v.as_str()))
                        .or_else(|| p.get("path").and_then(|v| v.as_str())))
                    .map(decode_v4_prop_path)
                    .unwrap_or_default();
                let status_num = v4_task_status_to_i32(&t.status);
                let files: Vec<serde_json::Value> = if let Some(v4_files) = dl
                    .and_then(|d| d.get("files"))
                    .and_then(|f| f.as_array())
                {
                    v4_files.iter().map(|f| {
                        let fname = f.get("name").and_then(|v| v.as_str()).unwrap_or(&name);
                        let fsize = f.get("size").and_then(|v| v.as_i64()).unwrap_or(total);
                        let fpath = if dst.is_empty() {
                            fname.to_string()
                        } else {
                            format!("{}/{}", dst.trim_end_matches('/'), fname)
                        };
                        let fcompleted = if status_num == 4 { fsize } else { 0 };
                        json!({
                            "index": f.get("index").and_then(|v| v.as_i64()).unwrap_or(0).to_string(),
                            "path": fpath,
                            "length": fsize.to_string(),
                            "completedLength": fcompleted.to_string(),
                            "selected": f.get("selected").and_then(|v| v.as_bool()).unwrap_or(true),
                            "uris": []
                        })
                    }).collect()
                } else {
                    let fpath = if dst.is_empty() { name.clone() } else { format!("{}/{}", dst.trim_end_matches('/'), name) };
                    let fcompleted = if status_num == 4 { total } else { 0 };
                    vec![json!({
                        "index": "0",
                        "path": fpath,
                        "length": total.to_string(),
                        "completedLength": fcompleted.to_string(),
                        "selected": true,
                        "uris": []
                    })]
                };
                json!({
                    "name": name,
                    "gid": t.id,
                    "status": status_num,
                    "total": total,
                    "task_status": status_num,
                    "task_error": t.error.as_deref().unwrap_or(""),
                    "files": files,
                    "create": t.created_at,
                    "update": t.updated_at,
                    "node": t.node.as_ref().map(|n| n.name.as_str()).unwrap_or(""),
                    "dst": dst
                })
            })
            .collect();
    serde_json::to_string(&tasks).map_err(|e| napi::Error::from_reason(e.to_string()))
}

#[napi]
pub async fn aria2_finished(_page: i32) -> napi::Result<String> {
    let api = get_client()?;
    if let Some(v3) = api.inner().as_v3() {
        let tasks = v3
            .list_finished()
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        serde_json::to_string(&tasks).map_err(|e| napi::Error::from_reason(e.to_string()))
    } else {
        let result = v4_aria2_finished(&api).await;
        match result {
            Err(_) => {
                if do_v4_refresh().await.is_ok() {
                    let api2 = get_client()?;
                    v4_aria2_finished(&api2).await
                } else {
                    result
                }
            }
            ok => ok,
        }
    }
}

#[napi]
pub async fn aria2_create_task(dst: String, urls: Vec<String>) -> napi::Result<()> {
    let api = get_client()?;
    if let Some(v3) = api.inner().as_v3() {
        let url_refs: Vec<&str> = urls.iter().map(String::as_str).collect();
        let req = Aria2CreateRequest {
            dst: &dst,
            url: url_refs,
        };
        v3.create_download(&req)
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))
    } else {
        let v4 = api.inner().as_v4()
            .ok_or_else(|| napi::Error::from_reason("not a v4 client"))?;
        let url_refs: Vec<&str> = urls.iter().map(String::as_str).collect();
        let req = CreateDownloadRequest {
            dst: &dst,
            src: url_refs,
            preferred_node_id: None,
        };
        v4.create_download(&req)
            .await
            .map(|_| ())
            .map_err(|e| napi::Error::from_reason(e.to_string()))
    }
}

#[napi]
pub async fn aria2_delete_task(gid: String) -> napi::Result<()> {
    let api = get_client()?;
    if let Some(v3) = api.inner().as_v3() {
        v3.delete_task(&gid)
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))
    } else {
        let v4 = api.inner().as_v4()
            .ok_or_else(|| napi::Error::from_reason("not a v4 client"))?;
        v4.cancel_download_task(&gid)
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))
    }
}

#[napi]
pub async fn get_user_tasks(page: i32) -> napi::Result<String> {
    let api = get_client()?;
    if let Some(v3) = api.inner().as_v3() {
        use cloudreve_api::api::v3::models::ApiResponse;
        use serde_json::Value;
        let url = format!("/user/setting/tasks?page={}", page);
        let resp: ApiResponse<Value> = v3
            .get(&url)
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        let data = resp.data.unwrap_or(Value::Null);
        serde_json::to_string(&data).map_err(|e| napi::Error::from_reason(e.to_string()))
    } else {
        let v4 = api.inner().as_v4()
            .ok_or_else(|| napi::Error::from_reason("not a v4 client"))?;
        let resp: V4ApiResponse<TaskListResponse> = v4.get("/workflow?page_size=100&category=general")
            .await
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        let response = resp.data.ok_or_else(|| napi::Error::from_reason(resp.msg.clone()))?;
        let tasks: Vec<serde_json::Value> = response.tasks.iter().map(|t| {
            let type_num = v4_task_type_to_i32(&t.r#type);
            let status_num = v4_task_status_to_i32(&t.status);
            let progress: i64 = t.summary.as_ref()
                .and_then(|s| s.props.get("progress"))
                .and_then(|v| v.as_i64())
                .unwrap_or(if status_num == 4 { 100 } else { 0 });
            json!({
                "status": status_num,
                "type": type_num,
                "create_date": t.created_at,
                "progress": progress,
                "error": t.error.as_deref().unwrap_or("")
            })
        }).collect();
        let total = tasks.len() as i64;
        let result = json!({ "tasks": tasks, "total": total });
        serde_json::to_string(&result).map_err(|e| napi::Error::from_reason(e.to_string()))
    }
}

// ---- Thumbnail ----

#[derive(Debug, serde::Deserialize)]
struct V4ThumbData {
    url: String,
}

/// Fetch thumbnail binary. For V3: direct GET with session cookie.
/// For V4: call /file/thumb to get pre-signed URL then fetch image bytes.
#[napi]
pub async fn get_thumb(id: String) -> napi::Result<String> {
    let api = get_client()?;
    if let Some(v3) = api.inner().as_v3() {
        // V3: return the thumb URL; caller adds cookie auth via system HTTP if possible
        Ok(format!("{}/api/v3/file/thumb/{}", v3.base_url, id))
    } else {
        let v4 = api.inner().as_v4()
            .ok_or_else(|| napi::Error::from_reason("not a v4 client"))?;
        let v4_uri = v4_path_to_uri(&id);
        let endpoint = format!("/file/thumb?uri={}&width=200&height=200", v4_uri);
        let resp: V4ApiResponse<V4ThumbData> = v4.get(&endpoint).await
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        // Return the pre-signed CDN URL — ArkTS createImageSource can fetch it without extra auth
        resp.data
            .ok_or_else(|| napi::Error::from_reason(resp.msg))
            .map(|d| d.url)
    }
}

// ---- V4 Exclusive: Share Links ----

/// Create a share link for a file or folder. Returns the share URL string.
#[napi]
pub async fn create_share_link(path: String, expire_days: i32, password: String) -> napi::Result<String> {
    let api = get_client()?;
    let v4 = api.inner().as_v4()
        .ok_or_else(|| napi::Error::from_reason("share links require V4"))?;
    let permissions = PermissionSetting {
        user_explicit: serde_json::json!({}),
        group_explicit: serde_json::json!({}),
        same_group: String::new(),
        other: String::new(),
        anonymous: String::new(),
        everyone: String::new(),
    };
    let req = CreateShareLinkRequest {
        permissions,
        uri: path,
        is_private: if password.is_empty() { None } else { Some(true) },
        share_view: None,
        expire: if expire_days > 0 { Some(expire_days as u32) } else { None },
        price: None,
        password: if password.is_empty() { None } else { Some(password) },
        show_readme: None,
    };
    v4.create_share_link(&req)
        .await
        .map_err(|e| napi::Error::from_reason(e.to_string()))
}

/// List current user's share links. Returns JSON array.
#[napi]
pub async fn list_share_links() -> napi::Result<String> {
    let api = get_client()?;
    let v4 = api.inner().as_v4()
        .ok_or_else(|| napi::Error::from_reason("share links require V4"))?;
    let links = v4
        .list_my_share_links()
        .await
        .map_err(|e| napi::Error::from_reason(e.to_string()))?;
    serde_json::to_string(&links).map_err(|e| napi::Error::from_reason(e.to_string()))
}

/// Delete a share link by ID.
#[napi]
pub async fn delete_share_link(share_id: String) -> napi::Result<()> {
    let api = get_client()?;
    let v4 = api.inner().as_v4()
        .ok_or_else(|| napi::Error::from_reason("share links require V4"))?;
    v4.delete_share_link(&share_id)
        .await
        .map_err(|e| napi::Error::from_reason(e.to_string()))
}

// ---- V4 Exclusive: Archive Operations ----

/// Create a server-side archive from given paths. Returns task ID.
#[napi]
pub async fn create_archive(src_paths: Vec<String>, dst_path: String) -> napi::Result<String> {
    let api = get_client()?;
    let v4 = api.inner().as_v4()
        .ok_or_else(|| napi::Error::from_reason("archive requires V4"))?;
    let src_refs: Vec<&str> = src_paths.iter().map(String::as_str).collect();
    let req = CreateArchiveRequest {
        src: src_refs,
        dst: &dst_path,
    };
    let task = v4
        .create_archive(&req)
        .await
        .map_err(|e| napi::Error::from_reason(e.to_string()))?;
    Ok(task.id)
}

/// Extract an archive to a destination path. Returns task ID.
#[napi]
pub async fn extract_archive(src_paths: Vec<String>, dst_path: String) -> napi::Result<String> {
    let api = get_client()?;
    let v4 = api.inner().as_v4()
        .ok_or_else(|| napi::Error::from_reason("archive requires V4"))?;
    let src_refs: Vec<&str> = src_paths.iter().map(String::as_str).collect();
    let req = ExtractArchiveRequest {
        src: src_refs,
        dst: &dst_path,
    };
    let task = v4
        .extract_archive(&req)
        .await
        .map_err(|e| napi::Error::from_reason(e.to_string()))?;
    Ok(task.id)
}

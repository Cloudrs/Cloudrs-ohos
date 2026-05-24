use napi_derive::napi;
use serde_json::{json, Value};
use crate::client::CloudreveClient;
use crate::types::*;

// ---- Configuration ----

#[napi]
pub fn set_base_url(url: String) {
    CloudreveClient::global().set_base_url(&url);
}

#[napi]
pub fn get_base_url() -> String {
    CloudreveClient::global().get_base_url()
}

#[napi]
pub fn set_cookie(cookie: String) {
    CloudreveClient::global().set_cookie(&cookie);
}

// ---- Site ----

#[napi]
pub async fn ping() -> napi::Result<String> {
    CloudreveClient::global()
        .get::<String>("/site/ping")
        .await
        .map_err(napi::Error::from_reason)
}

#[napi]
pub async fn get_site_config() -> napi::Result<String> {
    CloudreveClient::global()
        .get::<Value>("/site/config")
        .await
        .map(|v| v.to_string())
        .map_err(napi::Error::from_reason)
}

// ---- User ----

/// Returns [user_info_json, set_cookie_header]
#[napi]
pub async fn login(username: String, password: String) -> napi::Result<Vec<String>> {
    let body = LoginData {
        username,
        password,
        captcha_code: String::new(),
    };
    let (data, cookie) = CloudreveClient::global()
        .post::<Value, _>("/user/session", &body)
        .await
        .map_err(napi::Error::from_reason)?;
    Ok(vec![data.to_string(), cookie.unwrap_or_default()])
}

#[napi]
pub async fn get_user_storage() -> napi::Result<String> {
    CloudreveClient::global()
        .get::<Value>("/user/storage")
        .await
        .map(|v| v.to_string())
        .map_err(napi::Error::from_reason)
}

#[napi]
pub async fn get_user_setting() -> napi::Result<String> {
    CloudreveClient::global()
        .get::<Value>("/user/setting")
        .await
        .map(|v| v.to_string())
        .map_err(napi::Error::from_reason)
}

// ---- Directory / Files ----

#[napi]
pub async fn get_directory(path: String) -> napi::Result<String> {
    let url = format!("/directory{}", path);
    CloudreveClient::global()
        .get::<Value>(&url)
        .await
        .map(|v| v.to_string())
        .map_err(napi::Error::from_reason)
}

#[napi]
pub async fn get_object_detail(id: String, is_folder: bool) -> napi::Result<String> {
    let url = format!(
        "/object/property/{}?is_folder={}&trace_root=false",
        id, is_folder
    );
    CloudreveClient::global()
        .get::<Value>(&url)
        .await
        .map(|v| v.to_string())
        .map_err(napi::Error::from_reason)
}

// ---- Object operations ----

#[napi]
pub async fn delete_objects(items: Vec<String>, dirs: Vec<String>) -> napi::Result<()> {
    let src = ObjectSrc {
        items: if items.is_empty() { None } else { Some(items) },
        dirs: if dirs.is_empty() { None } else { Some(dirs) },
    };
    CloudreveClient::global()
        .delete::<Value, _>("/object", &src)
        .await
        .map(|_| ())
        .map_err(napi::Error::from_reason)
}

#[napi]
pub async fn move_objects(
    items: Vec<String>,
    dirs: Vec<String>,
    dst: String,
) -> napi::Result<()> {
    let mv = ObjectMove {
        src: ObjectSrc {
            items: if items.is_empty() { None } else { Some(items) },
            dirs: if dirs.is_empty() { None } else { Some(dirs) },
        },
        dst,
    };
    CloudreveClient::global()
        .patch::<Value, _>("/object", &mv)
        .await
        .map(|_| ())
        .map_err(napi::Error::from_reason)
}

#[napi]
pub async fn copy_objects(
    items: Vec<String>,
    dirs: Vec<String>,
    dst: String,
) -> napi::Result<()> {
    let cp = ObjectCopy {
        src: ObjectSrc {
            items: if items.is_empty() { None } else { Some(items) },
            dirs: if dirs.is_empty() { None } else { Some(dirs) },
        },
        dst,
    };
    CloudreveClient::global()
        .post::<Value, _>("/object/copy", &cp)
        .await
        .map(|_| ())
        .map_err(napi::Error::from_reason)
}

#[napi]
pub async fn rename_object(id: String, new_name: String, is_dir: bool) -> napi::Result<()> {
    let src = if is_dir {
        ObjectSrc {
            items: None,
            dirs: Some(vec![id]),
        }
    } else {
        ObjectSrc {
            items: Some(vec![id]),
            dirs: None,
        }
    };
    let rename = ObjectRename { src, new_name };
    CloudreveClient::global()
        .post::<Value, _>("/object/rename", &rename)
        .await
        .map(|_| ())
        .map_err(napi::Error::from_reason)
}

#[napi]
pub async fn new_directory(path: String) -> napi::Result<()> {
    let body = ObjectNew { path };
    CloudreveClient::global()
        .put::<Value, _>("/directory", &body)
        .await
        .map(|_| ())
        .map_err(napi::Error::from_reason)
}

#[napi]
pub async fn new_file(path: String) -> napi::Result<()> {
    let body = ObjectNew { path };
    CloudreveClient::global()
        .post::<Value, _>("/file/create", &body)
        .await
        .map(|_| ())
        .map_err(napi::Error::from_reason)
}

// ---- Download / Upload ----

#[napi]
pub async fn get_download_uri(id: String) -> napi::Result<String> {
    let url = format!("/file/download/{}", id);
    CloudreveClient::global()
        .put::<Value, _>(&url, &json!(null))
        .await
        .map(|v| v.as_str().unwrap_or("").to_string())
        .map_err(napi::Error::from_reason)
}

#[napi]
pub async fn get_upload_uri(
    path: String,
    size: u32,
    name: String,
    last_modified: u32,
    mime_type: String,
    chunk_size: u32,
) -> napi::Result<String> {
    let body = ObjectUpload {
        path,
        size: size as u64,
        name,
        last_modified: last_modified as u64,
        mime_type,
        chunk_size: chunk_size as u64,
    };
    CloudreveClient::global()
        .put::<Value, _>("/file/upload", &body)
        .await
        .map(|v| v.to_string())
        .map_err(napi::Error::from_reason)
}

// ---- Aria2 / Remote Download ----

#[napi]
pub async fn aria2_downloading() -> napi::Result<String> {
    CloudreveClient::global()
        .get::<Value>("/aria2/downloading")
        .await
        .map(|v| v.to_string())
        .map_err(napi::Error::from_reason)
}

#[napi]
pub async fn aria2_finished(page: i32) -> napi::Result<String> {
    let url = format!("/aria2/finished?page={}", page);
    CloudreveClient::global()
        .get::<Value>(&url)
        .await
        .map(|v| v.to_string())
        .map_err(napi::Error::from_reason)
}

#[napi]
pub async fn aria2_create_task(dst: String, urls: Vec<String>) -> napi::Result<()> {
    let body = json!({ "dst": dst, "url": urls });
    CloudreveClient::global()
        .post::<Value, _>("/aria2/url", &body)
        .await
        .map(|_| ())
        .map_err(napi::Error::from_reason)
}

#[napi]
pub async fn aria2_delete_task(gid: String) -> napi::Result<()> {
    let url = format!("/aria2/task/{}", gid);
    CloudreveClient::global()
        .delete::<Value, _>(&url, &json!(null))
        .await
        .map(|_| ())
        .map_err(napi::Error::from_reason)
}

#[napi]
pub async fn get_user_tasks(page: i32) -> napi::Result<String> {
    let url = format!("/user/setting/tasks?page={}", page);
    CloudreveClient::global()
        .get::<Value>(&url)
        .await
        .map(|v| v.to_string())
        .map_err(napi::Error::from_reason)
}

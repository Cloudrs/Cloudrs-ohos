use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize)]
pub struct BaseResponse<T> {
    pub code: i32,
    pub data: T,
    pub msg: String,
}

#[derive(Debug, Serialize)]
pub struct LoginData {
    pub username: String,
    pub password: String,
    #[serde(rename = "captchaCode")]
    pub captcha_code: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct UserInfo {
    pub id: String,
    pub user_name: String,
    pub nickname: String,
    pub status: i32,
    pub avatar: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct ObjectInfo {
    pub id: String,
    pub name: String,
    pub path: String,
    pub thumb: bool,
    pub size: u64,
    #[serde(rename = "type")]
    pub object_type: String,
    pub date: String,
    pub create_date: String,
    pub source_enabled: bool,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Policy {
    pub id: String,
    pub name: String,
    #[serde(rename = "type")]
    pub policy_type: String,
    pub max_size: u64,
    pub file_type: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct DirectoryInfo {
    pub parent: String,
    pub objects: Vec<ObjectInfo>,
    pub policy: Policy,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct UserStorage {
    pub used: u64,
    pub free: u64,
    pub total: u64,
}

#[derive(Debug, Serialize)]
pub struct ObjectSrc {
    pub items: Option<Vec<String>>,
    pub dirs: Option<Vec<String>>,
}

#[derive(Debug, Serialize)]
pub struct ObjectMove {
    pub src: ObjectSrc,
    pub dst: String,
}

#[derive(Debug, Serialize)]
pub struct ObjectCopy {
    pub src: ObjectSrc,
    pub dst: String,
}

#[derive(Debug, Serialize)]
pub struct ObjectNew {
    pub path: String,
}

#[derive(Debug, Serialize)]
pub struct ObjectRename {
    pub src: ObjectSrc,
    #[serde(rename = "newName")]
    pub new_name: String,
}

#[derive(Debug, Serialize)]
pub struct ObjectUpload {
    pub path: String,
    pub size: u64,
    pub name: String,
    #[serde(rename = "lastModified")]
    pub last_modified: u64,
    pub mime_type: String,
    #[serde(rename = "chunkSize")]
    pub chunk_size: u64,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Aria2Downloading {
    pub update: String,
    pub interval: i32,
    pub name: String,
    pub status: i32,
    pub dst: String,
    pub total: u64,
    pub downloaded: u64,
    pub speed: u64,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Aria2Finished {
    pub name: String,
    pub gid: String,
    pub status: i32,
    pub dst: String,
    pub error: String,
    pub total: u64,
    pub task_status: i32,
    pub task_error: String,
    pub create: String,
    pub update: String,
    pub node: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct UserTask {
    pub status: i32,
    #[serde(rename = "type")]
    pub task_type: i32,
    pub create_date: String,
    pub progress: i32,
    pub error: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct UserTasks {
    pub tasks: Vec<UserTask>,
    pub total: u64,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct UploadRequestResponse {
    #[serde(rename = "sessionId")]
    pub session_id: String,
    #[serde(rename = "chunkSize")]
    pub chunk_size: u64,
    pub expires: u64,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct ObjectDetail {
    pub created_at: String,
    pub updated_at: String,
    pub policy: String,
    pub size: u64,
    pub child_folder_num: u64,
    pub child_file_num: u64,
    pub path: String,
    pub query_date: String,
}

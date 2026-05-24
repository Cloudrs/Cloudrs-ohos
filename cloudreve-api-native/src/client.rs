use reqwest::{Client, Response, header};
use serde::{de::DeserializeOwned, Serialize};
use std::sync::{OnceLock, RwLock};
use crate::types::BaseResponse;

const API_PREFIX: &str = "/api/v3";
const SUCCESS_CODE: i32 = 0;
const DEFAULT_TIMEOUT_SECS: u64 = 30;

static CLIENT: OnceLock<CloudreveClient> = OnceLock::new();

pub struct CloudreveClient {
    inner: Client,
    base_url: RwLock<String>,
    cookie: RwLock<String>,
}

impl CloudreveClient {
    pub fn global() -> &'static CloudreveClient {
        CLIENT.get_or_init(|| CloudreveClient {
            inner: Client::builder()
                .timeout(std::time::Duration::from_secs(DEFAULT_TIMEOUT_SECS))
                .build()
                .expect("reqwest client init failed"),
            base_url: RwLock::new(String::new()),
            cookie: RwLock::new(String::new()),
        })
    }

    pub fn set_base_url(&self, url: &str) {
        *self.base_url.write().unwrap() = format!("{}{}", url.trim_end_matches('/'), API_PREFIX);
    }

    pub fn get_base_url(&self) -> String {
        self.base_url.read().unwrap().clone()
    }

    pub fn set_cookie(&self, cookie: &str) {
        *self.cookie.write().unwrap() = cookie.to_string();
    }

    pub fn get_cookie(&self) -> String {
        self.cookie.read().unwrap().clone()
    }

    fn url(&self, path: &str) -> String {
        format!("{}{}", self.base_url.read().unwrap(), path)
    }

    fn with_cookie(&self, builder: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        let c = self.get_cookie();
        if !c.is_empty() { builder.header(header::COOKIE, c) } else { builder }
    }

    pub async fn get<T: DeserializeOwned>(&self, path: &str) -> Result<T, String> {
        let resp = self.with_cookie(self.inner.get(self.url(path)))
            .send().await.map_err(|e| e.to_string())?;
        self.parse::<T>(resp).await
    }

    /// Returns (data, set-cookie header value)
    pub async fn post<T: DeserializeOwned, B: Serialize>(&self, path: &str, body: &B) -> Result<(T, Option<String>), String> {
        let resp = self.with_cookie(self.inner.post(self.url(path)))
            .json(body).send().await.map_err(|e| e.to_string())?;
        let set_cookie = resp.headers()
            .get(header::SET_COOKIE)
            .and_then(|v| v.to_str().ok())
            .map(String::from);
        let data = self.parse::<T>(resp).await?;
        Ok((data, set_cookie))
    }

    pub async fn put<T: DeserializeOwned, B: Serialize>(&self, path: &str, body: &B) -> Result<T, String> {
        let resp = self.with_cookie(self.inner.put(self.url(path)))
            .json(body).send().await.map_err(|e| e.to_string())?;
        self.parse::<T>(resp).await
    }

    pub async fn delete<T: DeserializeOwned, B: Serialize>(&self, path: &str, body: &B) -> Result<T, String> {
        let resp = self.with_cookie(self.inner.delete(self.url(path)))
            .json(body).send().await.map_err(|e| e.to_string())?;
        self.parse::<T>(resp).await
    }

    pub async fn patch<T: DeserializeOwned, B: Serialize>(&self, path: &str, body: &B) -> Result<T, String> {
        let resp = self.with_cookie(self.inner.patch(self.url(path)))
            .json(body).send().await.map_err(|e| e.to_string())?;
        self.parse::<T>(resp).await
    }

    async fn parse<T: DeserializeOwned>(&self, resp: Response) -> Result<T, String> {
        let status = resp.status();
        let base: BaseResponse<T> = resp.json().await.map_err(|e| e.to_string())?;
        if status.is_success() && base.code == SUCCESS_CODE {
            Ok(base.data)
        } else {
            Err(if base.msg.is_empty() {
                format!("HTTP {}", status)
            } else {
                base.msg
            })
        }
    }
}

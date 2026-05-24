#![deny(clippy::all)]

#[macro_use]
extern crate napi_derive;

#[napi]
pub fn hello() -> String {
    "cloudreve-api-native ready".to_string()
}

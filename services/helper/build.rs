fn main() {
    let core_sha256 = std::env::var("CORE_SHA256").unwrap_or_default();
    let core_name = std::env::var("CORE_NAME").unwrap_or_else(|_| "ShikooNetCore.exe".to_string());
    println!("cargo:rustc-env=CORE_SHA256={}", core_sha256);
    println!("cargo:rustc-env=CORE_NAME={}", core_name);
    println!("cargo:rerun-if-env-changed=CORE_SHA256");
    println!("cargo:rerun-if-env-changed=CORE_NAME");
    println!("cargo::rustc-check-cfg=cfg(shikoo_staging)");
    if std::env::var("SHIKOO_FLAVOR").as_deref() == Ok("staging") {
        println!("cargo:rustc-cfg=shikoo_staging");
    }
    println!("cargo:rerun-if-env-changed=SHIKOO_FLAVOR");
}

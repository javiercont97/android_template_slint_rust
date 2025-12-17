// Global static for JNI access to AppWindow (Weak reference)

slint::include_modules!();

#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub fn android_main(app: slint::android::AndroidApp) {
	slint::android::init(app).unwrap();
	
	let app = AppWindow::new().unwrap();
	app.run().unwrap();
}

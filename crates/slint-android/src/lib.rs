slint::include_modules!();

mod navigation_handler;

#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub fn android_main(app: slint::android::AndroidApp) {
	slint::android::init(app).unwrap();

	let app = AppWindow::new().unwrap();
	let app_weak = app.as_weak();

	// Initialize Rust-side navigation stack
	navigation_handler::init_navigation_state(app_weak.clone());

	// Handle navigation from UI
	let app_weak_nav = app_weak.clone();
	app.global::<PageNavigator>().on_navigate_to(move |page| {
		println!("UI Navigate to: {:?}", page);
		navigation_handler::push_page(page.clone());
		app_weak_nav
			.upgrade()
			.unwrap()
			.global::<PageNavigator>()
			.set_current_page(page);
	});

	// Handle back from UI
	let app_weak_back = app_weak.clone();
	app.global::<PageNavigator>().on_navigate_back(move || {
		println!("UI Navigate back");
		// We try to pop. `pop_page` should return the new top page if successful?
		// Or we use current_page helper.
		if navigation_handler::pop_page() {
			if let Some(top) = navigation_handler::current_page() {
				app_weak_back
					.upgrade()
					.unwrap()
					.global::<PageNavigator>()
					.set_current_page(top);
			}
		}
	});

	app.run().unwrap();
}

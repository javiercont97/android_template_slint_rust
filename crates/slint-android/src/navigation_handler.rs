use jni::{JNIEnv, objects::JClass, sys::jboolean};
use once_cell::sync::OnceCell;
use slint::{ComponentHandle, Weak};
use std::sync::Mutex;

use crate::{AppWindow, PageNavigator, Pages};

// Global stack
static NAVIGATION_STACK: OnceCell<Mutex<Vec<Pages>>> = OnceCell::new();
// Global app handle
static APP_HANDLE: OnceCell<Weak<AppWindow>> = OnceCell::new();

pub fn init_navigation_state(handle: Weak<AppWindow>) {
	APP_HANDLE.set(handle).ok();
	// Initialize stack with initial page (Counter)
	let stack = vec![Pages::COUNTER];
	NAVIGATION_STACK.set(Mutex::new(stack)).ok();
}

pub fn push_page(page: Pages) {
	if let Some(mutex) = NAVIGATION_STACK.get() {
		if let Ok(mut stack) = mutex.lock() {
			stack.push(page);
			println!(
				"Rust Stack: Push {:?}, Depth: {}",
				stack.last(),
				stack.len()
			);
		}
	}
}

pub fn pop_page() -> bool {
	if let Some(mutex) = NAVIGATION_STACK.get() {
		if let Ok(mut stack) = mutex.lock() {
			if stack.len() > 1 {
				stack.pop();
				println!("Rust Stack: Pop, New Depth: {}", stack.len());
				return true;
			}
		}
	}
	false
}

pub fn current_page() -> Option<Pages> {
	if let Some(mutex) = NAVIGATION_STACK.get() {
		if let Ok(stack) = mutex.lock() {
			return stack.last().cloned();
		}
	}
	None
}

// JNI Implementation
#[unsafe(no_mangle)]
pub extern "C" fn Java_slint_router_JNINavigationHandler_exitOnBack(
	_env: JNIEnv,
	_class: JClass,
) -> jboolean {
	println!("JNI: exitOnBack called");
	let should_exit = if let Some(mutex) = NAVIGATION_STACK.get() {
		let mut stack = mutex.lock().unwrap();
		if stack.len() > 1 {
			stack.pop();
			let new_top = stack.last().unwrap().clone();
			println!("JNI: Popping stack, returning to {:?}", new_top);

			// Trigger UI update
			if let Some(handle) = APP_HANDLE.get() {
				let handle_copy = handle.clone();
				let page_copy = new_top.clone();
				slint::invoke_from_event_loop(move || {
					if let Some(app) = handle_copy.upgrade() {
						app.global::<PageNavigator>().set_current_page(page_copy);
					}
				})
				.unwrap();
			}
			false
		} else {
			println!("JNI: Stack empty or at root, exiting app");
			true
		}
	} else {
		println!("JNI: Navigation stack not initialized, exiting");
		true
	};

	should_exit as jboolean
}

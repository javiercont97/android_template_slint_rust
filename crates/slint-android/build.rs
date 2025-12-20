use std::path::PathBuf;

fn main() {
	let ui_lib_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
		.join("../slint-ui/ui")
		.canonicalize()
		.unwrap_or_else(|_| PathBuf::from("../slint-ui/ui"));

	let config = slint_build::CompilerConfiguration::new()
		.with_library_paths([("slint-ui".into(), ui_lib_path)].into());

	slint_build::compile_with_config("ui/app.slint", config).expect("Slint compilation failed");
}

package com.slint_app.app;

import android.app.NativeActivity;
import android.os.Bundle;
import android.util.Log;

import slint.router.JNINavigationHandler;

public class MainActivity extends NativeActivity {

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		Log.d("NativeActivity", "onCreate called");
	}

	@Override
	public void onBackPressed() {
		boolean exit = JNINavigationHandler.exitOnBack();
		Log.d("NativeActivity", "Back pressed! exitOnBack: " + exit);
		if (exit) {
			super.onBackPressed();
		}
	}
}

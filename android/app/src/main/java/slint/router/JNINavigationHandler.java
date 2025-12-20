package slint.router;

public class JNINavigationHandler {
	public static native boolean exitOnBack();

    static {
        System.loadLibrary("slint_android");
    }
}

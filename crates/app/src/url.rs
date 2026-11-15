//! Opens a link in the browser through Android's own API (JNI, no Java code in the APK): the APK update is
//! downloaded and installed by the system from there. Compiled on every target so the desktop build checks it.
#![cfg_attr(not(target_os = "android"), allow(dead_code))]
use jni_sys::{jobject, jvalue, JNIEnv, JavaVM, JNI_OK};
use std::ffi::{c_void, CString};

/// # Safety
/// `vm` and `activity` must be the running app's JavaVM and Activity (android-activity's vm_as_ptr / activity_as_ptr).
pub unsafe fn open(vm: *mut c_void, activity: *mut c_void, url: &str) -> Result<(), String> {
    unsafe {
        let vm = vm as *mut JavaVM;
        let mut env: *mut JNIEnv = std::ptr::null_mut();
        let attach = (**vm).AttachCurrentThread.ok_or("AttachCurrentThread")?;
        if attach(vm, &mut env as *mut *mut JNIEnv as *mut *mut c_void, std::ptr::null_mut()) != JNI_OK {
            return Err("attach".into());
        }
        let f = &**env;
        let c = |s: &str| CString::new(s).unwrap_or_default();
        macro_rules! call {
            ($name:ident $(, $a:expr)*) => {
                (f.$name.ok_or(stringify!($name))?)(env $(, $a)*)
            };
        }
        let (uri_c, parse, sig) = (c("android/net/Uri"), c("parse"), c("(Ljava/lang/String;)Landroid/net/Uri;"));
        let uri_cls = call!(FindClass, uri_c.as_ptr());
        let parse = call!(GetStaticMethodID, uri_cls, parse.as_ptr(), sig.as_ptr());
        let u = c(url);
        let jurl = call!(NewStringUTF, u.as_ptr());
        let uri = call!(CallStaticObjectMethodA, uri_cls, parse, [jvalue { l: jurl }].as_ptr());
        let (int_c, init, isig) = (c("android/content/Intent"), c("<init>"), c("(Ljava/lang/String;Landroid/net/Uri;)V"));
        let intent_cls = call!(FindClass, int_c.as_ptr());
        let ctor = call!(GetMethodID, intent_cls, init.as_ptr(), isig.as_ptr());
        let act = c("android.intent.action.VIEW");
        let action = call!(NewStringUTF, act.as_ptr());
        let intent = call!(NewObjectA, intent_cls, ctor, [jvalue { l: action }, jvalue { l: uri }].as_ptr());
        let activity = activity as jobject;
        let act_cls = call!(GetObjectClass, activity);
        let (start, ssig) = (c("startActivity"), c("(Landroid/content/Intent;)V"));
        let start = call!(GetMethodID, act_cls, start.as_ptr(), ssig.as_ptr());
        call!(CallVoidMethodA, activity, start, [jvalue { l: intent }].as_ptr());
        if call!(ExceptionCheck) != 0 {
            call!(ExceptionClear);
            return Err("startActivity threw".into());
        }
        Ok(())
    }
}

/// Opens the game's activity anew in this same process, without closing the app: the restart intent of the launch
/// activity (Intent.makeRestartActivityTask: a fresh task, the old activity cleared). Its start runs the launcher
/// again, which loads the downloaded game library (a new file, so a new copy beside this one); the caller then ends
/// its own event loop, so this copy lets its activity go.
///
/// # Safety
/// as `open`
pub unsafe fn relaunch(vm: *mut c_void, activity: *mut c_void) -> Result<(), String> {
    unsafe {
        let vm = vm as *mut JavaVM;
        let mut env: *mut JNIEnv = std::ptr::null_mut();
        let attach = (**vm).AttachCurrentThread.ok_or("AttachCurrentThread")?;
        if attach(vm, &mut env as *mut *mut JNIEnv as *mut *mut c_void, std::ptr::null_mut()) != JNI_OK {
            return Err("attach".into());
        }
        let f = &**env;
        let c = |s: &str| CString::new(s).unwrap_or_default();
        macro_rules! call {
            ($name:ident $(, $a:expr)*) => {
                (f.$name.ok_or(stringify!($name))?)(env $(, $a)*)
            };
        }
        macro_rules! method {
            ($obj:expr, $name:expr, $sig:expr) => {{
                let cls = call!(GetObjectClass, $obj);
                let (n, s) = (c($name), c($sig));
                call!(GetMethodID, cls, n.as_ptr(), s.as_ptr())
            }};
        }
        let activity = activity as jobject;
        let pm = call!(CallObjectMethodA, activity, method!(activity, "getPackageManager", "()Landroid/content/pm/PackageManager;"), std::ptr::null());
        let pkg = call!(CallObjectMethodA, activity, method!(activity, "getPackageName", "()Ljava/lang/String;"), std::ptr::null());
        let launch = call!(CallObjectMethodA, pm, method!(pm, "getLaunchIntentForPackage", "(Ljava/lang/String;)Landroid/content/Intent;"), [jvalue { l: pkg }].as_ptr());
        if launch.is_null() {
            return Err("no launch intent".into());
        }
        let comp = call!(CallObjectMethodA, launch, method!(launch, "getComponent", "()Landroid/content/ComponentName;"), std::ptr::null());
        let (ic, mk, sig) = (c("android/content/Intent"), c("makeRestartActivityTask"), c("(Landroid/content/ComponentName;)Landroid/content/Intent;"));
        let intent_cls = call!(FindClass, ic.as_ptr());
        let mk = call!(GetStaticMethodID, intent_cls, mk.as_ptr(), sig.as_ptr());
        let intent = call!(CallStaticObjectMethodA, intent_cls, mk, [jvalue { l: comp }].as_ptr());
        call!(CallVoidMethodA, activity, method!(activity, "startActivity", "(Landroid/content/Intent;)V"), [jvalue { l: intent }].as_ptr());
        if call!(ExceptionCheck) != 0 {
            call!(ExceptionClear);
            return Err("restart threw".into());
        }
        log::info!("relaunching into the new game library");
        Ok(())
    }
}

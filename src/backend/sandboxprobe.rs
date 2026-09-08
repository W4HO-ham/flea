// Test-only: the one runtime probe the sandboxed tests share. bwrap sits on PATH inside a container
// and still cannot build a namespace there, so nine tests went red for the box and not for flea.
use crate::backend::sandbox::wrap_readonly;
use std::io::Write;
use std::path::Path;

// A program every Linux carries, run through the production jail so this is not a second sandbox.
const TRIVIAL: &str = "/usr/bin/true";

// Prints one line naming what is missing and answers true; on a box whose jail works it answers false.
pub fn skipped() -> bool {
    let why = match unusable() {
        None => return false,
        Some(why) => why,
    };
    // libtest names the thread after the test, so the line cannot drift from the test it belongs to.
    let who = std::thread::current().name().unwrap_or("a sandboxed test").to_string();
    // The handle and not eprintln!, which libtest captures and then throws away for a test that passes.
    let line = format!("SKIP {}: the bwrap sandbox cannot run here: {}\n", who, why);
    std::io::stderr().write_all(line.as_bytes()).ok();
    true
}

// The real wrapper argv and nothing else, so a box that can jail a process never skips a test.
fn unusable() -> Option<String> {
    let argv = wrap_readonly(&[TRIVIAL.to_string()], Path::new(TRIVIAL));
    let out = match std::process::Command::new(&argv[0]).args(&argv[1..]).output() {
        Ok(out) => out,
        Err(e) => return Some(format!("{} could not run: {}", argv[0], e)),
    };
    if out.status.success() {
        return None;
    }
    // Sample stderr: "bwrap: No permissions to create new namespace, likely because the kernel ...".
    let text = String::from_utf8_lossy(&out.stderr);
    Some(text.lines().next().unwrap_or("it exited non-zero and said nothing").to_string())
}

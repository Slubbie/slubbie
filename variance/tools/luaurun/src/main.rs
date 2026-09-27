//! luaurun: a minimal Luau runner for VARIANCE's headless tests.
//!
//! Globals provided to the script:
//!   __readfile(path) -> string?           read a UTF-8 file
//!   __writefile(path, text) -> boolean    write (replace) a file
//!   __listdir(path)  -> {{Name, Dir}}?    directory entries, sorted by name
//!   __compile(source, chunkname, env)     compile a chunk with its own environment
//!   __clock()        -> number            wall-clock seconds
//!   __exit(code)                          exit the process with a status code
//!   arg                                   extra command-line arguments
use mlua::prelude::*;
use std::fs;

fn main() -> LuaResult<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: luaurun <file.luau> [args...]");
        std::process::exit(2);
    }
    let lua = Lua::new();
    let globals = lua.globals();
    globals.set(
        "__readfile",
        lua.create_function(|_, path: String| Ok(fs::read_to_string(&path).ok()))?,
    )?;
    globals.set(
        "__writefile",
        lua.create_function(|_, (path, text): (String, LuaString)| {
            Ok(fs::write(&path, text.as_bytes()).is_ok())
        })?,
    )?;
    globals.set(
        "__listdir",
        lua.create_function(|lua, path: String| {
            let entries = match fs::read_dir(&path) {
                Ok(rd) => rd,
                Err(_) => return Ok(None),
            };
            let mut items: Vec<(String, bool)> = entries
                .filter_map(|e| e.ok())
                .map(|e| {
                    let dir = e.file_type().map(|t| t.is_dir()).unwrap_or(false);
                    (e.file_name().to_string_lossy().to_string(), dir)
                })
                .collect();
            items.sort();
            let t = lua.create_table()?;
            for (i, (name, dir)) in items.into_iter().enumerate() {
                let item = lua.create_table()?;
                item.set("Name", name)?;
                item.set("Dir", dir)?;
                t.set(i + 1, item)?;
            }
            Ok(Some(t))
        })?,
    )?;
    globals.set(
        "__compile",
        lua.create_function(|lua, (src, name, env): (String, String, LuaTable)| {
            let f = lua.load(&src).set_name(name).set_environment(env).into_function()?;
            Ok(f)
        })?,
    )?;
    globals.set(
        "__clock",
        lua.create_function(|_, ()| {
            Ok(std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs_f64())
                .unwrap_or(0.0))
        })?,
    )?;
    globals.set(
        "__exit",
        lua.create_function(|_, code: i32| -> LuaResult<()> { std::process::exit(code) })?,
    )?;
    let argt = lua.create_table()?;
    for (i, a) in args.iter().skip(2).enumerate() {
        argt.set(i + 1, a.clone())?;
    }
    globals.set("arg", argt)?;
    let src = fs::read_to_string(&args[1]).expect("cannot read file");
    match lua.load(&src).set_name(args[1].clone()).exec() {
        Ok(()) => Ok(()),
        Err(e) => {
            eprintln!("{}", e);
            std::process::exit(1);
        }
    }
}

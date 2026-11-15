//! The story of the web game, run as it is: QuickJS (rquickjs) loads the pack's `script/` modules (src/game/story.js
//! with its chapters, items.js, interaction_los.js and what they import) and `prelude.js` gives them the web game's
//! `G`. The native side feeds the hero every frame (`tick`), presses the action button (`act`), shows what comes
//! out (`drain` → [`Event`]) and answers the questions (`answer`).
use rquickjs::loader::{Loader, Resolver};
use rquickjs::module::Declared;
use rquickjs::{CatchResultExt, Context, Ctx, Function, Module, Object, Runtime};
use std::collections::HashMap;
use std::rc::Rc;

/// What the scripts need of the world.
pub trait World {
    /// dream-world voxel at voxel coordinates
    fn solid(&self, x: i32, y: i32, z: i32) -> bool;
    /// the ground under (x, z) in metres
    fn ground(&self, x: f32, z: f32) -> f32;
}

/// Something the player sees or answers.
#[derive(Debug, Clone, PartialEq)]
pub enum Event {
    Say { text: String, dur: f32, who: String },
    Objective(String),
    Toast(String),
    /// the action button: what it does here ("" = nothing near)
    Prompt { label: String, icon: String },
    /// a text to read; answered with `answer(id, true)` when closed
    Read { id: u32, title: String, paras: Vec<String>, night: bool },
    /// a thing to look at with its buttons (label, value); answered with the value pressed
    Inspect { id: u32, item: String, kicker: String, title: String, desc: String, buttons: Vec<(String, serde_json::Value)> },
    /// a story prop shown or hidden (model name, position)
    Prop { model: String, pos: [f32; 3], on: bool },
    Teleport { pos: [f32; 3], yaw: f32 },
    /// the backpack changed
    Inventory,
    Menu,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Item {
    pub id: String,
    pub name: String,
    pub desc: String,
    pub hint: String,
    pub seen: bool,
}

const PRELUDE: &str = include_str!("prelude.js");
const BOOT: &str = "import { setupStory } from 'game/story.js';\n\
import { ITEMS } from 'game/items.js';\n\
import { scoreInteractable } from 'game/interaction_los.js';\n\
await globalThis.__boot({ setupStory, ITEMS, scoreInteractable });\n";

/// module names are paths under script/ ("game/story.js"); imports are relative to the importing module
struct PackResolver;
impl Resolver for PackResolver {
    fn resolve<'js>(&mut self, _ctx: &Ctx<'js>, base: &str, name: &str, _attributes: Option<rquickjs::loader::ImportAttributes<'js>>) -> rquickjs::Result<String> {
        if !name.starts_with('.') {
            return Ok(name.to_string());
        }
        let mut parts: Vec<&str> = base.split('/').collect();
        parts.pop();
        for p in name.split('/') {
            match p {
                "." | "" => {}
                ".." => {
                    parts.pop();
                }
                _ => parts.push(p),
            }
        }
        Ok(parts.join("/"))
    }
}

struct PackLoader(Rc<HashMap<String, String>>);
impl Loader for PackLoader {
    fn load<'js>(&mut self, ctx: &Ctx<'js>, name: &str, _attributes: Option<rquickjs::loader::ImportAttributes<'js>>) -> rquickjs::Result<Module<'js, Declared>> {
        let src = self.0.get(name).ok_or_else(|| rquickjs::Error::new_loading(name))?;
        Module::declare(ctx.clone(), name, src.as_str())
    }
}

/// (the context is dropped before its runtime)
pub struct Script {
    ctx: Context,
    rt: Runtime,
}

fn err<'js>(ctx: &Ctx<'js>, e: rquickjs::Error) -> String {
    match Err::<(), _>(e).catch(ctx) {
        Err(e) => e.to_string(),
        Ok(()) => String::new(),
    }
}

impl Script {
    /// `sources`: path under script/ → module source
    pub fn new(sources: HashMap<String, String>, world: Rc<dyn World>) -> Result<Self, String> {
        let rt = Runtime::new().map_err(|e| e.to_string())?;
        rt.set_loader(PackResolver, PackLoader(Rc::new(sources)));
        let ctx = Context::full(&rt).map_err(|e| e.to_string())?;
        ctx.with(|ctx| -> Result<(), String> {
            let host = Object::new(ctx.clone()).map_err(|e| e.to_string())?;
            let w = world.clone();
            let solid = Function::new(ctx.clone(), move |x: i32, y: i32, z: i32| w.solid(x, y, z)).map_err(|e| e.to_string())?;
            let w = world.clone();
            let ground = Function::new(ctx.clone(), move |x: f64, z: f64| w.ground(x as f32, z as f32) as f64).map_err(|e| e.to_string())?;
            let log = Function::new(ctx.clone(), |t: String| log::info!("{t}")).map_err(|e| e.to_string())?;
            host.set("solid", solid).map_err(|e| e.to_string())?;
            host.set("ground", ground).map_err(|e| e.to_string())?;
            host.set("log", log).map_err(|e| e.to_string())?;
            ctx.globals().set("__host", host).map_err(|e| e.to_string())?;
            ctx.eval::<(), _>(PRELUDE).map_err(|e| format!("prelude: {}", err(&ctx, e)))?;
            // the module promise settles once the story is set up (running the pending jobs below)
            Module::evaluate(ctx.clone(), "boot", BOOT).map_err(|e| format!("boot: {}", err(&ctx, e)))?;
            Ok(())
        })?;
        let s = Script { ctx, rt };
        s.jobs();
        s.ctx.with(|ctx| -> Result<(), String> {
            let ready: bool = ctx.eval("typeof G.story === 'object'").map_err(|e| err(&ctx, e))?;
            if ready { Ok(()) } else { Err("the story did not set up (see the log)".into()) }
        })?;
        Ok(s)
    }

    fn jobs(&self) {
        loop {
            match self.rt.execute_pending_job() {
                Ok(true) => {}
                Ok(false) => break,
                Err(e) => log::warn!("script job: {e}"),
            }
        }
    }

    fn call<A: for<'js> rquickjs::function::IntoArgs<'js>>(&self, name: &str, args: A) {
        self.ctx.with(|ctx| {
            let r = ctx.globals().get::<_, Function>(name).and_then(|f| f.call::<_, rquickjs::Value>(args));
            if let Err(e) = r {
                log::warn!("{name}: {}", err(&ctx, e));
            }
        });
        self.jobs();
    }

    fn string(&self, name: &str, args: Option<&str>) -> String {
        self.ctx.with(|ctx| {
            let r = ctx.globals().get::<_, Function>(name).and_then(|f| match args {
                Some(a) => f.call::<_, String>((a,)),
                None => f.call::<_, String>(()),
            });
            r.unwrap_or_else(|e| {
                log::warn!("{name}: {}", err(&ctx, e));
                String::new()
            })
        })
    }

    pub fn new_game(&self) {
        self.call("__newGame", ());
    }

    /// every frame of play: feet, facing, camera and its forward vector
    pub fn tick(&self, dt: f32, pos: [f32; 3], yaw: f32, cam: [f32; 3], fwd: [f32; 3]) {
        self.call("__cam", (cam[0], cam[1], cam[2], fwd[0], fwd[1], fwd[2]));
        self.call("__tick", (dt, pos[0], pos[1], pos[2], yaw));
    }

    pub fn act(&self) {
        self.call("__act", ());
    }

    pub fn answer(&self, id: u32, value: &serde_json::Value) {
        self.ctx.with(|ctx| {
            let r = ctx.json_parse(value.to_string()).and_then(|v| ctx.globals().get::<_, Function>("__answer").and_then(|f| f.call::<_, ()>((id, v))));
            if let Err(e) = r {
                log::warn!("answer: {}", err(&ctx, e));
            }
        });
        self.jobs();
    }

    /// what the scripts said since the last call
    pub fn drain(&self) -> Vec<Event> {
        let s = self.string("__drain", None);
        if s.is_empty() {
            return Vec::new();
        }
        let v: Vec<serde_json::Value> = serde_json::from_str(&s).unwrap_or_default();
        v.iter().filter_map(event).collect()
    }

    pub fn inventory(&self) -> Vec<Item> {
        let v: Vec<serde_json::Value> = serde_json::from_str(&self.string("__inventory", None)).unwrap_or_default();
        v.iter()
            .map(|i| {
                let s = |k: &str| i[k].as_str().unwrap_or("").to_string();
                Item { id: s("id"), name: s("name"), desc: s("desc"), hint: s("hint"), seen: i["seen"].as_bool().unwrap_or(false) }
            })
            .collect()
    }

    pub fn seen(&self, id: &str) {
        self.call("__seen", (id.to_string(),));
    }

    /// the story's state for a save (chapter, flags, backpack, world edits, the memory board)
    pub fn serialize(&self) -> String {
        self.string("__serialize", None)
    }

    pub fn restore(&self, json: &str) {
        self.call("__restore", (json.to_string(),));
    }
}

fn event(e: &serde_json::Value) -> Option<Event> {
    let s = |k: &str| e[k].as_str().unwrap_or("").to_string();
    let f = |k: &str| e[k].as_f64().unwrap_or(0.0) as f32;
    let id = e["id"].as_u64().unwrap_or(0) as u32;
    let p = |k: &str| {
        let a = &e[k];
        [0, 1, 2].map(|i| a[i].as_f64().unwrap_or(0.0) as f32)
    };
    Some(match e["t"].as_str()? {
        "say" => Event::Say { text: s("text"), dur: f("dur").max(1.0), who: s("who") },
        "objective" => Event::Objective(s("text")),
        "toast" => Event::Toast(s("text")),
        "prompt" => Event::Prompt { label: s("label"), icon: s("icon") },
        "read" => Event::Read { id, title: s("title"), paras: e["paras"].as_array()?.iter().map(|x| x.as_str().unwrap_or("").to_string()).collect(), night: e["night"].as_bool().unwrap_or(false) },
        "inspect" => Event::Inspect {
            id,
            item: s("item"),
            kicker: s("kicker"),
            title: s("title"),
            desc: s("desc"),
            buttons: e["buttons"].as_array()?.iter().map(|b| (b[0].as_str().unwrap_or("").to_string(), b[1].clone())).collect(),
        },
        "prop" => Event::Prop { model: s("model"), pos: p("p"), on: e["on"].as_bool().unwrap_or(true) },
        "teleport" => Event::Teleport { pos: p("p"), yaw: f("yaw") },
        "inv" => Event::Inventory,
        "menu" => Event::Menu,
        _ => return None,
    })
}

/// the pack's script/ files as `Script::new` takes them
pub fn sources(pack: &mezdu_core::Pack) -> Result<HashMap<String, String>, String> {
    let mut m = HashMap::new();
    for f in pack.manifest.of_kind("script") {
        let src = String::from_utf8(pack.read(&f.path)?).map_err(|e| format!("{}: {e}", f.path))?;
        m.insert(f.path.trim_start_matches("script/").to_string(), src);
    }
    if m.is_empty() {
        return Err("the pack has no story scripts".into());
    }
    Ok(m)
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Flat;
    impl World for Flat {
        fn solid(&self, _x: i32, y: i32, _z: i32) -> bool {
            y < 0
        }
        fn ground(&self, _x: f32, _z: f32) -> f32 {
            7.0
        }
    }

    /// MEZDU_PACK=<pack with script/> cargo test -p mezdu-script -- --nocapture
    #[test]
    fn story_runs() {
        let Ok(dir) = std::env::var("MEZDU_PACK") else { return };
        let pack = mezdu_core::Pack::open(&dir).unwrap();
        let s = Script::new(sources(&pack).unwrap(), Rc::new(Flat)).unwrap();
        s.new_game();
        let props = s.drain().iter().filter(|e| matches!(e, Event::Prop { .. })).count();
        assert!(props > 0);
        // the study desk of chapter 1 (ch1.js: m(364), floor + 0.7, m(2204))
        let found = s.ctx.with(|ctx| ctx.eval::<Vec<f64>, _>("G.interactables.find(i => String(typeof i.label === 'function' ? i.label() : i.label).startsWith('Стол в кабинете')).pos").unwrap());
        let (x, y, z) = (found[0] as f32, found[1] as f32, found[2] as f32);
        let feet = [x - 1.0, y - 0.7, z];
        s.tick(0.1, feet, std::f32::consts::FRAC_PI_2, [x - 3.0, y + 1.0, z], [1.0, 0.0, 0.0]);
        let ev = s.drain();
        assert!(ev.iter().any(|e| matches!(e, Event::Prompt { label, .. } if label.starts_with("Стол"))), "{ev:?}");
        s.act();
        let mut asked = None;
        for _ in 0..40 {
            s.tick(0.5, feet, 1.57, [x - 3.0, y + 1.0, z], [1.0, 0.0, 0.0]);
            for e in s.drain() {
                if let Event::Inspect { id, item, .. } = &e {
                    assert_eq!(item, "student_pass");
                    asked = Some(*id);
                }
            }
            if let Some(id) = asked.take() {
                s.answer(id, &serde_json::Value::Bool(true));
            }
        }
        let inv = s.inventory();
        eprintln!("backpack after the desk: {inv:?}");
        assert!(inv.iter().any(|i| i.id == "student_pass"), "{inv:?}");
        let save = s.serialize();
        s.new_game();
        assert!(s.inventory().is_empty());
        s.restore(&save);
        assert_eq!(s.inventory().len(), inv.len());
    }
}

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
    /// a voxel at voxel coordinates is solid in the world `w` (0 dream, 1 nightmare)
    fn solid(&self, x: i32, y: i32, z: i32, w: u8) -> bool;
    /// a hazard (deep water, a gorge) at (x, y, z) metres in the world `w`
    fn hazard(&self, x: f32, y: f32, z: f32, w: u8) -> bool;
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
    /// a conversation with a witness (story/dialogue.js): answered with {"ask": i}, {"record": true} or {"leave": true}
    Dialog { id: u32, role: String, name: String, context: String, speech: String, questions: Vec<(String, bool)>, testimony: Testimony },
    /// a story prop shown or hidden (model name, position)
    Prop { model: String, pos: [f32; 3], on: bool },
    /// the hero put somewhere; `safe`: on ground near there where the whole body fits (main.js placeSafe)
    Teleport { pos: [f32; 3], yaw: f32, safe: bool },
    /// the screen darkens (1) or clears (0) over `dur` seconds
    Fade { to: f32, dur: f32 },
    /// a story prop moved and turned (a door on its hinge): found by where it was placed (`home`)
    Move { model: String, home: [f32; 3], to: [f32; 3], yaw: f32 },
    /// a story box the hero cannot walk through while `on` (min x y z, max x y z)
    Collider { id: u32, aabb: [f32; 6], on: bool },
    /// the mind gave out (stability 0): the hero collapses back to the road (not ported yet)
    Collapse,
    /// a world edit (worldgen.js EDIT_BOXES) opened or closed
    Edit { name: String, on: bool },
    /// the backpack changed
    Inventory,
    Menu,
    /// the story's figures (G.figures) changed: their model names, in list order (`Script::figures` gives where
    /// the visible ones stand, by index into this list)
    Figures(Vec<String>),
}

/// A witness or NPC where the story put it (creatures.js Figures)
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Figure {
    pub idx: usize,
    pub pos: [f32; 3],
    pub yaw: f32,
    pub mask: u32,
    pub scale: f32,
}

/// The dream and the nightmare as the scripts have them (the web's Duality): where the hero stands, the transition
/// wave (a sphere whose inside shows the target world) and its reversed outer front, the stability of the mind.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct WorldState {
    /// the world at the hero's head is the nightmare
    pub night: bool,
    /// 0 dream .. 1 nightmare, eased (the sky, the light and the exposure follow it)
    pub night_share: f32,
    pub wave_c: [f32; 3],
    pub wave_r: f32,
    /// world ids: 0 dream, 1 nightmare
    pub wave_from: u8,
    pub wave_to: u8,
    pub wave_active: bool,
    /// the world the chunks show when no wave runs
    pub base: u8,
    /// outer front of a reversed wave (radius 0 = none)
    pub wave2_c: [f32; 3],
    pub wave2_r: f32,
    /// 0..100: the mind; the nightmare drains it
    pub stability: f32,
    /// «вглядеться» is on
    pub peering: bool,
    /// which worlds the chunks show: 1 dream, 2 nightmare, 3 both (per pixel) — main.js cullMask
    pub cull: u32,
    /// «вглядеться» is offered now (the story's flag, the chapters up to 8, no cinematic)
    pub eye_available: bool,
    /// 0..1: the hero left the story path (the frame blurs, main.js S.blur)
    pub headache: f32,
    /// a cinematic or a collapse holds the hero (no walking)
    pub locked: bool,
}

/// The testimony button of a conversation.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Testimony {
    None,
    Offer,
    Recorded,
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
import { Duality } from 'game/duality.js';\n\
import * as WR from 'game/world_rules.js';\n\
import * as PR from 'game/play_rules.js';\n\
await globalThis.__boot({ setupStory, ITEMS, scoreInteractable, Duality, WR, PR });\n";

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
            let solid = Function::new(ctx.clone(), move |x: i32, y: i32, z: i32, wo: i32| w.solid(x, y, z, wo as u8)).map_err(|e| e.to_string())?;
            let wz = world.clone();
            let hazard = Function::new(ctx.clone(), move |x: f64, y: f64, z: f64, wo: i32| wz.hazard(x as f32, y as f32, z as f32, wo as u8)).map_err(|e| e.to_string())?;
            host.set("hazard", hazard).map_err(|e| e.to_string())?;
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

    /// every frame of play: the camera (position, forward vector), then the hero (feet, facing) and «вглядеться»
    /// held or not. Afterwards `world` reads what the frame needs.
    #[allow(clippy::too_many_arguments)]
    pub fn tick(&self, dt: f32, pos: [f32; 3], yaw: f32, cam: [f32; 3], fwd: [f32; 3], eye: bool, on_ground: bool) {
        self.call("__cam", (cam[0], cam[1], cam[2], fwd[0], fwd[1], fwd[2]));
        self.call("__tick", (dt, pos[0], pos[1], pos[2], yaw, eye, on_ground));
    }

    /// the visible figures after the last tick: (index into the last `Event::Figures` list, x, y, z, yaw, mask,
    /// scale), written into `out` (cleared first; no allocation once it has grown)
    pub fn figures(&self, out: &mut Vec<Figure>) {
        out.clear();
        self.ctx.with(|ctx| {
            let Ok(a) = ctx.globals().get::<_, rquickjs::TypedArray<f64>>("__FIG") else { return };
            // SAFETY: as in `world`
            let v = unsafe { a.as_slice() };
            let n = v.first().map_or(0, |&n| n as usize).min((v.len().saturating_sub(1)) / 7);
            for k in 0..n {
                let o = 1 + k * 7;
                out.push(Figure { idx: v[o] as usize, pos: [v[o + 1] as f32, v[o + 2] as f32, v[o + 3] as f32], yaw: v[o + 4] as f32, mask: v[o + 5] as u32, scale: v[o + 6] as f32 });
            }
        });
    }

    /// the world as the scripts have it after the last tick (no allocation: the script keeps one array)
    pub fn world(&self) -> WorldState {
        self.ctx.with(|ctx| {
            let Ok(st) = ctx.globals().get::<_, rquickjs::TypedArray<f64>>("__ST") else { return WorldState::default() };
            // SAFETY: the array lives in the script's globals and is only read here, between two script calls
            let v = unsafe { st.as_slice() };
            if v.len() < 23 {
                return WorldState::default();
            }
            let f = |i: usize| v[i] as f32;
            WorldState {
                night: v[0] > 0.5,
                night_share: f(1),
                wave_c: [f(2), f(3), f(4)],
                wave_r: f(5),
                wave_from: f(6) as u8,
                wave_to: f(7) as u8,
                wave_active: v[8] > 0.5,
                base: f(9) as u8,
                wave2_c: [f(10), f(11), f(12)],
                wave2_r: f(13),
                stability: f(14),
                peering: v[16] > 0.5,
                cull: v[18] as u32,
                eye_available: v[20] > 0.5,
                headache: f(21),
                locked: v[22] > 0.5,
            }
        })
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
        "dialog" => Event::Dialog {
            id,
            role: s("role"),
            name: s("name"),
            context: s("context"),
            speech: s("speech"),
            questions: e["questions"].as_array()?.iter().map(|q| (q[0].as_str().unwrap_or("").to_string(), q[1].as_bool().unwrap_or(false))).collect(),
            testimony: match e["testimony"].as_str().unwrap_or("") {
                "offer" => Testimony::Offer,
                "recorded" => Testimony::Recorded,
                _ => Testimony::None,
            },
        },
        "prop" => Event::Prop { model: s("model"), pos: p("p"), on: e["on"].as_bool().unwrap_or(true) },
        "teleport" => Event::Teleport { pos: p("p"), yaw: f("yaw"), safe: e["safe"].as_bool().unwrap_or(false) },
        "fade" => Event::Fade { to: f("to"), dur: f("dur") },
        "move" => Event::Move { model: s("model"), home: p("p"), to: p("to"), yaw: f("yaw") },
        "collider" => {
            let b = &e["box"];
            Event::Collider { id, aabb: [0, 1, 2, 3, 4, 5].map(|i| b[i].as_f64().unwrap_or(0.0) as f32), on: e["on"].as_bool().unwrap_or(true) }
        }
        "collapse" => Event::Collapse,
        "edit" => Event::Edit { name: s("name"), on: e["on"].as_bool().unwrap_or(false) },
        "inv" => Event::Inventory,
        "menu" => Event::Menu,
        "figures" => Event::Figures(e["models"].as_array()?.iter().map(|x| x.as_str().unwrap_or("").to_string()).collect()),
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
        fn solid(&self, _x: i32, y: i32, _z: i32, _w: u8) -> bool {
            y < 0
        }
        fn hazard(&self, _x: f32, _y: f32, _z: f32, _w: u8) -> bool {
            false
        }
        fn ground(&self, _x: f32, _z: f32) -> f32 {
            7.0
        }
    }

    /// MEZDU_PACK=<pack with script/> cargo test -p mezdu-script -- --nocapture
    #[test]
    fn story_runs() {
        let Ok(dir) = std::env::var("MEZDU_PACK") else { return };
        let _ = env_logger::builder().is_test(true).try_init();
        let pack = mezdu_core::Pack::open(&dir).unwrap();
        let s = Script::new(sources(&pack).unwrap(), Rc::new(Flat)).unwrap();
        s.new_game();
        let props = s.drain().iter().filter(|e| matches!(e, Event::Prop { .. })).count();
        assert!(props > 0);
        // the study desk of chapter 1 (ch1.js: m(364), floor + 0.7, m(2204))
        let found = s.ctx.with(|ctx| ctx.eval::<Vec<f64>, _>("G.interactables.find(i => String(typeof i.label === 'function' ? i.label() : i.label).startsWith('Стол в кабинете')).pos").unwrap());
        let (x, y, z) = (found[0] as f32, found[1] as f32, found[2] as f32);
        let feet = [x - 1.0, y - 0.7, z];
        s.tick(0.1, feet, std::f32::consts::FRAC_PI_2, [x - 3.0, y + 1.0, z], [1.0, 0.0, 0.0], false, true);
        let ev = s.drain();
        assert!(ev.iter().any(|e| matches!(e, Event::Prompt { label, .. } if label.starts_with("Стол"))), "{ev:?}");
        s.act();
        let mut asked = None;
        for _ in 0..40 {
            s.tick(0.5, feet, 1.57, [x - 3.0, y + 1.0, z], [1.0, 0.0, 0.0], false, true);
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

#[cfg(test)]
mod nightmare {
    use super::*;

    struct Flat;
    impl World for Flat {
        fn solid(&self, _x: i32, y: i32, _z: i32, _w: u8) -> bool {
            y < 0
        }
        fn hazard(&self, _x: f32, _y: f32, _z: f32, _w: u8) -> bool {
            false
        }
        fn ground(&self, _x: f32, _z: f32) -> f32 {
            7.0
        }
    }

    /// «вглядеться» (R) turns the world around the hero's head into the nightmare, then the dream comes back
    /// (main.js peer / stopPeer): MEZDU_PACK=<pack with script/> cargo test -p mezdu-script
    #[test]
    fn peering_turns_the_world() {
        let Ok(dir) = std::env::var("MEZDU_PACK") else { return };
        let pack = mezdu_core::Pack::open(&dir).unwrap();
        let s = Script::new(sources(&pack).unwrap(), Rc::new(Flat)).unwrap();
        s.new_game();
        let pos = [56.0, 7.0, 279.0];
        let fwd = [1.0, 0.0, 0.0];
        // a few frames of the dream
        for _ in 0..3 {
            s.tick(0.1, pos, 0.0, pos, fwd, false, true);
        }
        let w = s.world();
        assert!(!w.night && w.cull == 1 && w.base == 0, "{w:?}");
        // hold R: the nightmare comes in around the hero (the wave grows)
        s.tick(0.1, pos, 0.0, pos, fwd, true, true);
        let mut grew = false;
        for _ in 0..30 {
            s.tick(0.1, pos, 0.0, pos, fwd, false, true);
            let w = s.world();
            if w.wave_active && w.wave_r > 0.0 {
                grew = true;
                assert_eq!(w.cull, 3, "the wave shows both worlds");
            }
        }
        assert!(grew, "the wave runs");
        // the stability drops while looking (-3 at the start, then the nightmare drains)
        assert!(s.world().peering);
        let before = s.world().stability;
        for _ in 0..40 {
            s.tick(0.5, pos, 0.0, pos, fwd, false, true);
        }
        assert!(s.world().stability < before, "the nightmare drains the mind");
        // R again: back to the dream
        s.tick(0.1, pos, 0.0, pos, fwd, true, true);
        for _ in 0..200 {
            s.tick(0.1, pos, 0.0, pos, fwd, false, true);
        }
        let w = s.world();
        assert!(!w.peering, "{w:?}");
        assert_eq!(w.base, 0, "{w:?}");
        assert!(!w.wave_active, "{w:?}");
    }
}

#[cfg(test)]
mod path {
    use super::*;

    struct Flat;
    impl World for Flat {
        fn solid(&self, _x: i32, y: i32, _z: i32, _w: u8) -> bool {
            y < 0
        }
        fn hazard(&self, _x: f32, _y: f32, _z: f32, _w: u8) -> bool {
            false
        }
        fn ground(&self, _x: f32, _z: f32) -> f32 {
            7.0
        }
    }

    /// Far from the story path the headache grows, the frame blurs, then the hero collapses and is put back on the
    /// path (play_rules.js updateHeadache / collapseToRoute): MEZDU_PACK=<pack with script/> cargo test -p mezdu-script
    #[test]
    fn leaving_the_path_hurts_and_brings_back() {
        let Ok(dir) = std::env::var("MEZDU_PACK") else { return };
        let pack = mezdu_core::Pack::open(&dir).unwrap();
        let s = Script::new(sources(&pack).unwrap(), Rc::new(Flat)).unwrap();
        s.new_game();
        s.drain();
        // 32 m from the nearest route of chapter 1, outside the open settlement
        let far = [100.0, 7.0, 100.0];
        let (mut said, mut faded, mut back) = (false, false, None);
        let mut max_h: f32 = 0.0;
        for _ in 0..200 {
            s.tick(0.1, far, 0.0, far, [1.0, 0.0, 0.0], false, true);
            max_h = max_h.max(s.world().headache);
            for e in s.drain() {
                match e {
                    Event::Say { text, .. } if text.contains("Виски") => said = true,
                    Event::Fade { to, .. } if to > 0.5 => faded = true,
                    Event::Teleport { pos, safe: true, .. } => back = Some(pos),
                    _ => {}
                }
            }
            if back.is_some() {
                break;
            }
        }
        assert!(max_h > 0.9 && said && faded, "headache {max_h}, said {said}, faded {faded}");
        let p = back.expect("put back on the path");
        assert!((p[0] - far[0]).hypot(p[2] - far[2]) > 5.0, "{p:?}");
    }
}

#[cfg(test)]
mod dialogue {
    use super::*;

    struct Flat;
    impl World for Flat {
        fn solid(&self, _x: i32, y: i32, _z: i32, _w: u8) -> bool {
            y < 0
        }
        fn hazard(&self, _x: f32, _y: f32, _z: f32, _w: u8) -> bool {
            false
        }
        fn ground(&self, _x: f32, _z: f32) -> f32 {
            7.0
        }
    }

    /// A witness of chapter 1: the conversation opens, a question changes what they say, the testimony is recorded,
    /// «Отойти» ends it (story/dialogue.js through G.ui.dialog): MEZDU_PACK=<pack> cargo test -p mezdu-script
    #[test]
    fn a_witness_talks() {
        let Ok(dir) = std::env::var("MEZDU_PACK") else { return };
        let pack = mezdu_core::Pack::open(&dir).unwrap();
        let s = Script::new(sources(&pack).unwrap(), Rc::new(Flat)).unwrap();
        s.new_game();
        let models = s.drain().into_iter().filter_map(|e| if let Event::Figures(m) = e { Some(m) } else { None }).last().unwrap_or_default();
        let anna = models.iter().position(|m| m == "figure_anna").expect("Анна stands in chapter 1");
        let pos = s.ctx.with(|ctx| ctx.eval::<Vec<f64>, _>("G.interactables.find(i => String(typeof i.label === 'function' ? i.label() : i.label).includes('Анна')).pos").unwrap());
        let (x, y, z) = (pos[0] as f32, pos[1] as f32, pos[2] as f32);
        let feet = [x - 0.6, y - 1.0, z];
        let fwd = [1.0, 0.0, 0.0];
        s.tick(0.1, feet, std::f32::consts::FRAC_PI_2, [x - 3.0, y + 1.0, z], fwd, false, true);
        assert!(s.drain().iter().any(|e| matches!(e, Event::Prompt { label, .. } if label.contains("Анна"))));
        let mut figs = Vec::new();
        s.figures(&mut figs);
        let f = figs.iter().find(|f| f.idx == anna).expect("her figure is drawn");
        assert!((f.pos[0] - x).abs() < 2.0 && (f.pos[2] - z).abs() < 2.0, "where she talks: {:?} vs {x} {z}", f.pos);
        // she turns to the hero (figures.js onUpdate)
        assert!((f.yaw - (feet[0] - f.pos[0]).atan2(feet[2] - f.pos[2])).abs() < 1e-3);
        s.act();
        let next = |s: &Script| loop {
            s.tick(0.1, feet, 1.57, [x - 3.0, y + 1.0, z], fwd, false, true);
            if let Some(d) = s.drain().into_iter().find(|e| matches!(e, Event::Dialog { .. })) {
                return d;
            }
        };
        let Event::Dialog { id, speech: first, questions, testimony, .. } = next(&s) else { unreachable!() };
        assert!(!questions.is_empty() && testimony == Testimony::Offer);
        s.answer(id, &serde_json::json!({ "ask": 0 }));
        let Event::Dialog { id, speech, questions, .. } = next(&s) else { unreachable!() };
        assert_ne!(speech, first, "the answer is shown");
        assert!(questions[0].1, "the question is ticked");
        s.answer(id, &serde_json::json!({ "record": true }));
        let Event::Dialog { id, testimony, .. } = next(&s) else { unreachable!() };
        assert_eq!(testimony, Testimony::Recorded);
        s.answer(id, &serde_json::json!({ "leave": true }));
        s.tick(0.1, feet, 1.57, [x - 3.0, y + 1.0, z], fwd, false, true);
        assert!(!s.world().locked, "the hero walks again");
    }
}

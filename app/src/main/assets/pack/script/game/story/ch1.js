// CHAPTER 1: ПОНЕДЕЛЬНИК — ПОРОГ (Suburban House, Yard & University)
import { P, VS } from '../../world/layout.js';
import { m } from './common.js';

const CH1_H = P.ch1House;
const ch1FloorY = 7.0;    // 1st floor (y = 56, 56 * 0.125 = 7.0m, 3.75m ceiling height)
const ch1Floor2Y = 11.0;  // 2nd floor (y = 88, 88 * 0.125 = 11.0m, 3.25m ceiling height)
const ch1BasementY = 3.625; // Basement walking surface (y = 29, 29 * 0.125 = 3.625m, 3.25m ceiling height)

export function setupChapter1(ctx) {
  const { registerChapterExit } = ctx;
  const placeInteractiveDoor = makeDoorPlacer(ctx);
  const ch1FrontDoorState = placeHouseDoors(ctx, placeInteractiveDoor);
  placeUpperDoors(placeInteractiveDoor);
  const props = placeHouseRooms(ctx);
  placeTown(ctx, placeInteractiveDoor);
  clueInteractions(ctx, props);
  roomInteractions(ctx, props);
  yardInteractions(ctx, props);
  townInteractions(ctx, props);
  // Chapter 1 Exit Gateway at University Archway (north side of square)
  registerChapterExit(
    1,
    [m(400), ch1FloorY + 1.0, m(2096)],
    'Арка Университета: войти в Архив карт (Глава 2 →)',
    'Арка Университета (предъявите студенческий билет и зафиксируйте вывод в Дневнике J)'
  );
  const { ch1PassProp, ch1SedativeProp, ch1ReceiptProp } = props;
  return { CH1_H, ch1Floor2Y, ch1FrontDoorState, ch1PassProp, ch1SedativeProp, ch1ReceiptProp };
}

function makeDoorPlacer({ G, say, once }) {
  // Reusable helper for interactive, smoothly animated hinge-pivoted doors with stationary molded casing frames
  const placeInteractiveDoor = (opts) => {
    const {
      id,
      kind = 'interior', // 'front' | 'interior' | 'garage' | 'basement'
      axis,              // 'z' (wall along X at zw, opening x0..x0+7) | 'x' (wall along Z at xw, opening z0..z0+7)
      xw,
      zw,
      open0,             // start voxel of 8-voxel doorway (x0 for 'z' wall, z0 for 'x' wall)
      y = ch1FloorY,
      swingDir = 1,      // +1 or -1 around hinge
      startOpen = false,
      name = 'Дверь',
      descOpen = null,
      customCheck = null,
    } = opts;

    const frameModel = `door_frame_${kind}`;
    const leafModel = `door_${kind}`;

    let fx, fz, fyaw, hx, hz, closedYaw, ix, iz, cx0, cx1, cz0, cz1;
    if (axis === 'z') {
      fx = (open0 + 4) * VS;
      fz = (zw + 0.5) * VS;
      fyaw = 0;
      hx = (open0 + 0.7) * VS; // the hinge at the inner face of the jamb (door models: DOOR_VS in library.js)
      hz = (zw + 0.5) * VS;
      closedYaw = 0;
      ix = fx;
      iz = fz;
      cx0 = open0 * VS;
      cx1 = (open0 + 8) * VS;
      cz0 = (zw - 0.8) * VS;
      cz1 = (zw + 1.8) * VS;
    } else {
      fx = (xw + 0.5) * VS;
      fz = (open0 + 4) * VS;
      fyaw = Math.PI / 2;
      hx = (xw + 0.5) * VS;
      hz = (open0 + 0.7) * VS;
      closedYaw = -Math.PI / 2;
      ix = fx;
      iz = fz;
      cx0 = (xw - 0.8) * VS;
      cx1 = (xw + 1.8) * VS;
      cz0 = open0 * VS;
      cz1 = (open0 + 8) * VS;
    }

    const openYaw = closedYaw + swingDir * Math.PI * 0.48;
    const initYaw = startOpen ? openYaw : closedYaw;

    const frameProp = G.place(frameModel, fx, y, fz, fyaw, { mask: 3 });
    const leafProp = G.place(leafModel, hx, y, hz, initYaw, { mask: 3 });
    const col = (G.world && G.world.addCollider)
      ? G.world.addCollider({ x0: cx0, x1: cx1, y0: y, y1: y + 2.125, z0: cz0, z1: cz1, mask: startOpen ? 0 : 3, tag: 'door_' + id })
      : null;

    const state = {
      id,
      open: startOpen,
      animating: false,
      curYaw: initYaw,
      closedYaw,
      openYaw,
      hx,
      y,
      hz,
      frameProp,
      leafProp,
      col,
      setInstant(isOpen) {
        this.open = !!isOpen;
        this.curYaw = this.open ? this.openYaw : this.closedYaw;
        if (this.leafProp) this.leafProp.move(this.hx, this.y, this.hz, this.curYaw);
        if (this.col) this.col.mask = this.open ? 0 : 3;
      },
      async animateTo(targetOpen) {
        if (this.animating) return;
        this.animating = true;
        this.open = !!targetOpen;
        if (this.col) this.col.mask = this.open ? 0 : 3;
        G.audio.sfx('door');
        const fromYaw = this.curYaw;
        const toYaw = this.open ? this.openYaw : this.closedYaw;
        const steps = 16;
        const dt = 0.38 / steps;
        for (let s = 1; s <= steps; s++) {
          const u = s / steps;
          const ease = u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2;
          this.curYaw = fromYaw + (toYaw - fromYaw) * ease;
          if (this.leafProp) this.leafProp.move(this.hx, this.y, this.hz, this.curYaw);
          await G.wait(dt);
        }
        this.curYaw = toYaw;
        if (this.leafProp) this.leafProp.move(this.hx, this.y, this.hz, this.curYaw);
        this.animating = false;
      },
    };

    G.interact({
      pos: [ix, y + 1.05, iz],
      r: 2.35,
      world: 'any',
      icon: 'door',
      cond: () => G.chapter === 1,
      label: () => {
        if (customCheck) {
          const customLbl = customCheck.label(state);
          if (customLbl) return customLbl;
        }
        return state.open ? `Закрыть дверь: ${name}` : `Открыть дверь: ${name}`;
      },
      run: async () => {
        if (customCheck && customCheck.beforeToggle) {
          const allowed = await customCheck.beforeToggle(state);
          if (!allowed) return;
        }
        const nextOpen = !state.open;
        await state.animateTo(nextOpen);
        if (nextOpen && descOpen && once('door_desc_' + id)) {
          say(descOpen, 3.8);
        }
      },
    });

    return state;
  };
  return placeInteractiveDoor;
}

// the front door and the doors of the ground floor
function placeHouseDoors({ G, say }, placeInteractiveDoor) {
  // 1. ALL HOUSE & NEIGHBORHOOD DOORS (Molded 3D frames, double-sided handles, mosaic glass & smooth hinge animation)
  // 1a. Front Entrance Door (North wall z=2194, opening x=404..411) — locked until key from behind mirror is used
  const ch1FrontDoorState = placeInteractiveDoor({
    id: 'front_main',
    kind: 'front',
    axis: 'z',
    zw: 2194,
    open0: 404,
    y: ch1FloorY,
    swingDir: -1, // swings South into Grand Hallway
    startOpen: false,
    name: 'Парадный вход дома',
    customCheck: {
      label: (st) => {
        if (!G.edits.ch1Door) {
          if (!G.flags.ch1AnsweringHeard || !G.has('student_pass')) return 'Парадная дверь (сначала проверьте автоответчик и возьмите студбилет в кабинете)';
          if (!G.has('apartment_key')) return 'Парадная дверь заперта (найдите латунный ключ за зеркалом в прихожей)';
          return 'Отпереть замок латунным ключом и распахнуть парадную дверь';
        }
        return st.open ? 'Закрыть парадную дверь' : 'Открыть парадную дверь';
      },
      beforeToggle: async () => {
        if (!G.edits.ch1Door) {
          if (!G.flags.ch1AnsweringHeard || !G.has('student_pass')) {
            G.audio.sfx('click');
            say('Нельзя уходить без документов. Нужно прослушать автоответчик и забрать студенческий билет со стола в кабинете на первом этаже.', 3.8);
            G.objective('Осмотреть письменный стол в кабинете на 1-м этаже и забрать студенческий билет');
            return false;
          }
          if (!G.has('apartment_key')) {
            G.audio.sfx('click');
            say('Замок намертво заперт. Запасной латунный ключ всегда лежал в тайнике за зеркалом в прихожей (вглядитесь в зеркало — R / Глаз)…', 4.0);
            G.objective('Осмотреть зеркало в прихожей и достать ключ из тайника');
            return false;
          }
          G.flags.ch1BoltUnlocked = true;
          G.audio.sfx('break');
          await G.setEdit('ch1Door', true);
          if (G.peering) G.stopPeer();
          say('Латунный ключ провернулся в замке! Входная дверь плавно распахивается, с улицы тянет свежим осенним воздухом и запахом клёнов.', 4.2);
          G.objective('Выйти на улицу к Университету, поговорить с соседями и сделать вывод в Дневнике (J)');
        }
        return true;
      },
    },
  });

  // 1b. 1st-Floor Interior Doors
  placeInteractiveDoor({
    id: 'living_room',
    kind: 'interior',
    axis: 'x',
    xw: 424,
    open0: 2208,
    y: ch1FloorY,
    swingDir: 1, // swings East into Living Room
    startOpen: true,
    name: 'Гостиная с камином',
  });
  placeInteractiveDoor({
    id: 'kitchen_hall',
    kind: 'interior',
    axis: 'x',
    xw: 424,
    open0: 2258,
    y: ch1FloorY,
    swingDir: 1, // swings East into Kitchen
    startOpen: true,
    name: 'Кухня и столовая',
  });
  placeInteractiveDoor({
    id: 'back_patio',
    kind: 'interior',
    axis: 'z',
    zw: 2290,
    open0: 448,
    y: ch1FloorY,
    swingDir: 1, // swings North into Kitchen
    startOpen: false,
    name: 'Выход на заднюю террасу и в сад',
    // locked until the front door is open: the way out of the house goes through the key behind the mirror
    customCheck: {
      label: () => (G.edits.ch1Door ? null : 'Дверь на террасу заперта снаружи'),
      beforeToggle: async () => {
        if (G.edits.ch1Door) return true;
        G.audio.sfx('click');
        say('Заперто снаружи на висячий замок — сквозь стекло видна дужка. Выйти можно только через парадную дверь.', 3.6);
        return false;
      },
    },
    descOpen: 'Дверь на задний двор распахнута. На каменной террасе за домом пахнет осенней листвой и влажной травой.',
  });
  placeInteractiveDoor({
    id: 'study_hall',
    kind: 'interior',
    axis: 'x',
    xw: 392,
    open0: 2208,
    y: ch1FloorY,
    swingDir: -1, // swings West into Study
    startOpen: true,
    name: 'Рабочий кабинет Элиаса',
  });
  placeInteractiveDoor({
    id: 'garage_walkin',
    kind: 'garage',
    axis: 'x',
    xw: 336,
    open0: 2212,
    y: ch1FloorY,
    swingDir: -1, // swings West into Attached Garage
    startOpen: false,
    name: 'Пристроенный гараж и мастерская',
    descOpen: 'Огнестойкая дверь ведет прямо в пристроенный гараж дома. Внутри пахнет машинным маслом и древесиной верстака.',
  });
  placeInteractiveDoor({
    id: 'toilet_1f',
    kind: 'interior',
    axis: 'x',
    xw: 392,
    open0: 2246,
    y: ch1FloorY,
    swingDir: -1, // swings West into 1st-Floor Toilet #1
    startOpen: false,
    name: 'Гостевой санузел (1-й этаж)',
  });
  placeInteractiveDoor({
    id: 'bathroom_1f',
    kind: 'interior',
    axis: 'x',
    xw: 392,
    open0: 2272,
    y: ch1FloorY,
    swingDir: -1, // swings West into 1st-Floor Full Bathroom
    startOpen: false,
    name: 'Ванная комната (1-й этаж)',
  });
  placeInteractiveDoor({
    id: 'basement_stairs',
    kind: 'basement',
    axis: 'z',
    zw: 2256,
    open0: 400,
    y: ch1FloorY,
    swingDir: 1, // swings North into Hallway away from stairs
    startOpen: false,
    name: 'Лестница в подвал и фотолабораторию',
    descOpen: 'Тяжелая дубовая дверь с кованым засовом открывает широкую каменную лестницу в подвальную фотолабораторию.',
  });

  return ch1FrontDoorState;
}

// doors of the upper floor
function placeUpperDoors(placeInteractiveDoor) {
  // 1c. 2nd-Floor Interior Doors
  placeInteractiveDoor({
    id: 'master_bedroom_2f',
    kind: 'interior',
    axis: 'x',
    xw: 424,
    open0: 2258,
    y: ch1Floor2Y,
    swingDir: 1, // swings East into Master Bedroom
    startOpen: true,
    name: 'Главная спальня Элиаса (2-й этаж)',
  });
  placeInteractiveDoor({
    id: 'guest_bedroom_2f',
    kind: 'interior',
    axis: 'x',
    xw: 392,
    open0: 2258,
    y: ch1Floor2Y,
    swingDir: -1, // swings West into Guest Bedroom
    startOpen: false,
    name: 'Гостевая спальня (2-й этаж)',
  });
  placeInteractiveDoor({
    id: 'toilet_2f',
    kind: 'interior',
    axis: 'z',
    zw: 2220,
    open0: 400,
    y: ch1Floor2Y,
    swingDir: 1, // swings North into 2nd-Floor Toilet #2
    startOpen: false,
    name: 'Санузел второго этажа',
  });
}

// furniture of every room, the yard, the street and the square; returns the props the interactions use
function placeHouseRooms({ G }) {
  // 2. TOILETS & WASHBASINS (Flush against walls in 1st-Floor Toilet #1 and 2nd-Floor Toilet #2)
  // 1st Floor Toilet #1 (x: 336..392, z: 2238..2262) — Toilet against West wall (x=336), Washbasin against North wall (z=2238)
  G.place('toilet', m(340), ch1FloorY, m(2250), Math.PI / 2, { mask: 3 });
  G.place('washbasin', m(364), ch1FloorY, m(2241.4), 0, { mask: 3 });
  G.light({ pos: [m(364), ch1FloorY + 3.2, m(2250)], r: 6.0, col: [0.9, 0.94, 1.0], k: 1.8, mask: 3 });

  // 2nd Floor Toilet #2 (x: 392..424, z: 2194..2220) — Toilet against North wall (z=2194), Washbasin against West wall (x=392)
  G.place('toilet', m(414), ch1Floor2Y, m(2198), 0, { mask: 3 });
  G.place('washbasin', m(395.4), ch1Floor2Y, m(2206), Math.PI / 2, { mask: 3 });
  G.light({ pos: [m(408), ch1Floor2Y + 2.8, m(2206)], r: 6.0, col: [0.9, 0.94, 1.0], k: 1.8, mask: 3 });

  // 3. 1ST FLOOR — LIVING ROOM (x: 424..484, z: 2194..2244 — Generous spacing between sofa, coffee table, and fireplace)
  G.place('fireplace', m(481), ch1FloorY, m(2220), -Math.PI / 2, { mask: 3 });
  G.light({ pos: [m(478), ch1FloorY + 1.2, m(2220)], r: 7.5, col: [1.0, 0.58, 0.2], k: 2.5, mask: 1, flicker: true });
  G.place('sofa', m(446), ch1FloorY, m(2220), Math.PI / 2, { mask: 1 });
  G.place('sofa_torn', m(446), ch1FloorY, m(2220), Math.PI / 2, { mask: 2 });
  G.place('table', m(460), ch1FloorY, m(2220), Math.PI / 2, { mask: 1 });
  G.place('table_broken', m(460), ch1FloorY, m(2220), Math.PI / 2 + 0.15, { mask: 2 });
  G.place('bookshelf', m(435), ch1FloorY, m(2197.2), 0, { mask: 3 }); // Flush against North wall (z=2194)
  G.light({ pos: [m(454), ch1FloorY + 3.3, m(2220)], r: 9.5, col: [1.0, 0.66, 0.22], k: 2.65, mask: 1 });
  G.light({ pos: [m(454), ch1FloorY + 3.3, m(2220)], r: 9.0, col: [0.25, 0.45, 0.95], k: 2.2, mask: 2, flicker: true });

  // 4. 1ST FLOOR — KITCHEN & DINING (x: 424..484, z: 2244..2290 — Counter & Fridge flush against East wall x=484, Dining Table centered with full clearance)
  G.place('kitchen_counter', m(481.2), ch1FloorY, m(2272), -Math.PI / 2, { mask: 3, scale: 1.0 });
  const ch1FridgeProp = G.place('refrigerator', m(480.8), ch1FloorY, m(2254), -Math.PI / 2, { mask: 3 });
  G.place('table', m(446), ch1FloorY, m(2268), 0, { mask: 1 });
  G.place('table_broken', m(446), ch1FloorY, m(2268), 0.1, { mask: 2 });
  G.place('chair', m(446), ch1FloorY, m(2275), Math.PI, { mask: 1 });
  G.place('teapot', m(446.8), ch1FloorY + 0.64, m(2268), -0.3, { mask: 3, scale: 1.25 });
  const ch1Cup = G.place('teacup', m(445.4), ch1FloorY + 0.64, m(2268), 0.4, { mask: 3, scale: 1.4 });
  G.light({ pos: [m(454), ch1FloorY + 3.3, m(2268)], r: 9.0, col: [1.0, 0.65, 0.22], k: 2.60, mask: 1 });
  G.light({ pos: [m(454), ch1FloorY + 3.3, m(2268)], r: 8.5, col: [0.3, 0.6, 0.95], k: 2.2, mask: 2, flicker: true });

  // 5. 1ST FLOOR — FULL BATHROOM (x: 336..392, z: 2262..2290 — Bathtub flush against West wall x=336, Washbasin flush against North wall z=2262)
  G.place('bathtub', m(340.2), ch1FloorY, m(2276), Math.PI / 2, { mask: 3, scale: 1.0 });
  G.place('washbasin', m(368), ch1FloorY, m(2265.4), 0, { mask: 3 });
  G.light({ pos: [m(364), ch1FloorY + 3.3, m(2276)], r: 7.0, col: [0.85, 0.92, 1.0], k: 2.0, mask: 1 });
  G.light({ pos: [m(364), ch1FloorY + 3.3, m(2276)], r: 7.0, col: [0.15, 0.4, 0.8], k: 2.2, mask: 2, flicker: true });

  // 6. 1ST FLOOR — STUDY / HOME OFFICE (x: 336..392, z: 2194..2238 — Bookshelves flush against South wall z=2238, Desk by North window)
  G.place('table', m(364), ch1FloorY, m(2205), 0, { mask: 1 });
  G.place('table_broken', m(364), ch1FloorY, m(2205), 0.2, { mask: 2 });
  G.place('chair', m(364), ch1FloorY, m(2199.5), 0, { mask: 1 });
  G.place('bookshelf', m(352), ch1FloorY, m(2235.5), Math.PI, { mask: 3 });
  G.place('bookshelf', m(376), ch1FloorY, m(2235.5), Math.PI, { mask: 3 });
  G.place('answering_machine', m(363.2), ch1FloorY + 0.64, m(2205), 0, { mask: 3 });
  const ch1PassProp = G.place('item_student_card', m(364.8), ch1FloorY + 0.65, m(2205), 0.2, { mask: 3, scale: 2.2, pitch: -Math.PI / 2, highlight: true });
  G.light({ pos: [m(364), ch1FloorY + 3.3, m(2216)], r: 8.5, col: [1.0, 0.66, 0.22], k: 2.55, mask: 1 });
  G.light({ pos: [m(364), ch1FloorY + 3.3, m(2216)], r: 8.0, col: [0.25, 0.5, 0.95], k: 2.2, mask: 2, flicker: true });

  // 7. 1ST FLOOR — CENTRAL GRAND HALLWAY (x: 392..424, z: 2194..2290 — Mirror flush on West wall x=392, Grandfather Clock flush on North wall z=2194)
  const ch1MirrorProp = G.place('mirror_wall', m(393.4), ch1FloorY + 1.25, m(2201), Math.PI / 2, { mask: 3, scale: 1.3 });
  const ch1ClockProp = G.place('grandfather_clock', m(418), ch1FloorY, m(2197), 0, { mask: 3 });
  G.light({ pos: [m(406), ch1FloorY + 3.3, m(2214)], r: 9.2, col: [1.0, 0.66, 0.22], k: 2.65, mask: 1 });
  G.light({ pos: [m(406), ch1FloorY + 3.3, m(2214)], r: 8.5, col: [0.25, 0.45, 0.9], k: 2.2, mask: 2, flicker: true });

  // 8. ATTACHED GARAGE (x: 298..336, z: 2198..2262 — Parked wagon + Workbench flush against South wall z=2262)
  G.place('car_wagon', m(317), ch1FloorY, m(2224), -Math.PI / 2, { mask: 3 });
  G.place('workbench', m(316), ch1FloorY, m(2258.5), Math.PI, { mask: 3 });
  G.place('tool_crowbar', m(316), ch1FloorY + 0.88, m(2258.5), 0.4, { mask: 3, scale: 1.4 });
  G.light({ pos: [m(317), ch1FloorY + 3.4, m(2230)], r: 8.5, col: [0.92, 0.94, 0.98], k: 2.1, mask: 3 });

  // 9. 2ND FLOOR — MASTER BEDROOM SUITE (x: 424..484, z: 2194..2290 — Bed centered against solid East wall between windows)
  G.place('bed', m(477.5), ch1Floor2Y, m(2220), -Math.PI / 2, { mask: 3, scale: 1.15 });
  G.place('drawers', m(481.6), ch1Floor2Y, m(2200), -Math.PI / 2, { mask: 1 });
  G.place('drawers_burnt', m(481.6), ch1Floor2Y, m(2200), -Math.PI / 2, { mask: 2 });
  const ch1SedativeProp = G.place('item_cassette', m(481.6), ch1Floor2Y + 0.88, m(2200), 0.5, { mask: 3, scale: 1.6, highlight: true });

  // Wall Calendar mounted flush on North wall (z=2194)
  G.place('wall_calendar', m(436), ch1Floor2Y + 1.38, m(2195.2), 0, { mask: 3 });

  // Dresser (with auto-repair receipt) & Oak Wardrobe flush against West wall (x=424)
  G.place('drawers', m(427.2), ch1Floor2Y, m(2216), Math.PI / 2, { mask: 1 });
  G.place('drawers_burnt', m(427.2), ch1Floor2Y, m(2216), Math.PI / 2, { mask: 2 });
  const ch1ReceiptProp = G.place('item_letter_dream', m(427.2), ch1Floor2Y + 0.88, m(2216), 0.3, { mask: 3, scale: 2.0, pitch: -Math.PI / 2, highlight: true });
  G.place('wardrobe', m(427.6), ch1Floor2Y, m(2238), Math.PI / 2, { mask: 3 });

  // Bookshelf flush against South wall (z=2290)
  G.place('bookshelf', m(472), ch1Floor2Y, m(2287.5), Math.PI, { mask: 3 });
  G.light({ pos: [m(454), ch1Floor2Y + 2.9, m(2234)], r: 10.0, col: [1.0, 0.67, 0.23], k: 2.75, mask: 1 });
  G.light({ pos: [m(454), ch1Floor2Y + 2.9, m(2234)], r: 9.5, col: [0.25, 0.45, 0.9], k: 2.2, mask: 2, flicker: true });

  // 10. 2ND FLOOR — GUEST BEDROOM & UPPER LANDING (x: 336..392, z: 2194..2290)
  G.place('bed', m(342.6), ch1Floor2Y, m(2212), Math.PI / 2, { mask: 3, scale: 1.0 });
  G.place('drawers', m(339.2), ch1Floor2Y, m(2201), Math.PI / 2, { mask: 3 });
  G.place('wardrobe', m(389.2), ch1Floor2Y, m(2226), -Math.PI / 2, { mask: 3 });
  G.light({ pos: [m(364), ch1Floor2Y + 2.9, m(2234)], r: 9.0, col: [1.0, 0.66, 0.22], k: 2.55, mask: 3 });
  G.light({ pos: [m(406), ch1Floor2Y + 2.9, m(2256)], r: 8.5, col: [1.0, 0.66, 0.22], k: 2.55, mask: 3 });

  // 11. BASEMENT (x: 344..476, z: 2204..2288, y = 3.625m — 3.25m high ceiling!)
  G.place('table', m(372), ch1BasementY, m(2208.5), 0, { mask: 3 });
  G.place('photo_enlarger', m(372), ch1BasementY + 0.64, m(2208.5), 0, { mask: 3 });
  G.place('workbench', m(440), ch1BasementY, m(2208.5), 0, { mask: 3 });
  G.place('chest_open', m(472), ch1BasementY, m(2232), -Math.PI / 2, { mask: 3 });
  G.light({ pos: [m(372), ch1BasementY + 2.6, m(2224)], r: 8.0, col: [1.0, 0.15, 0.1], k: 2.7, mask: 3, flicker: true });
  G.light({ pos: [m(440), ch1BasementY + 2.6, m(2224)], r: 8.0, col: [0.9, 0.75, 0.45], k: 2.1, mask: 3 });
  G.light({ pos: [m(404), ch1BasementY + 2.6, m(2268)], r: 8.0, col: [0.35, 0.55, 0.85], k: 2.1, mask: 3 });

  // 12. PORCH, PRIVATE YARD, BACKYARD PATIO, DRIVEWAY & SUBURBAN SQUARE ROAD LOOP
  G.place('bicycle', m(395), ch1FloorY, m(2189), 0.25, { mask: 3, scale: 1.0 });
  G.place('mailbox', m(398), ch1FloorY, m(2178.5), 0, { mask: 3, scale: 1.0 });
  G.place('phone_booth', m(422), ch1FloorY, m(2178), 0, { mask: 3 });
  G.place('bench', m(452), ch1FloorY, m(2299), Math.PI, { mask: 3 }); // Backyard patio bench

  // Full-Size Parked Vehicles along the Square Road Loop curbs (clear of crosswalks and sidewalks)
  G.place('car_sedan', m(352), ch1FloorY, m(2171), 0, { mask: 3, scale: 1.0 });
  G.place('car_wagon', m(452), ch1FloorY, m(2158), Math.PI, { mask: 3, scale: 1.0 });
  G.place('car_sedan', m(236), ch1FloorY, m(2171), 0, { mask: 3, scale: 1.0 });

  // Municipal Fire Hydrants on sidewalks
  G.place('fire_hydrant', m(386), ch1FloorY, m(2177.5), 0, { mask: 3, scale: 1.0 });
  G.place('fire_hydrant', m(432), ch1FloorY, m(2151), 0, { mask: 3, scale: 1.0 });

  // Tall 4.2m Streetlamps along sidewalks around the Square Road Loop (lights at y + 3.85m!)
  for (const [lx, lz, lyaw] of [
    [396, 2178, 0],
    [328, 2178, 0],
    [474, 2178, 0],
    [360, 2151, Math.PI],
    [438, 2151, Math.PI],
    [336, 2126, 0],
    [452, 2126, 0],
    [268, 2140, Math.PI / 2],
    [516, 2140, -Math.PI / 2],
  ]) {
    G.place('lantern_post', m(lx), ch1FloorY, m(lz), lyaw, { mask: 3 });
    G.light({ pos: [m(lx), ch1FloorY + 3.85, m(lz)], r: 9.5, col: [1, 0.78, 0.45], k: 2.2, mask: 3 });
  }

  // Park Bench & Leah's Scarf on the Central Neighborhood Park Square
  G.place('bench', m(406), ch1FloorY, m(2144), 0, { mask: 3 });
  const ch1ScarfProp = G.place('item_petal_pink', m(406), ch1FloorY + 0.55, m(2144), 0.4, { mask: 3, scale: 2.0, highlight: true });
  return { ch1FridgeProp, ch1Cup, ch1PassProp, ch1MirrorProp, ch1ClockProp, ch1SedativeProp, ch1ReceiptProp, ch1ScarfProp };
}

// walk-in buildings around the square
function placeTown({ G }, placeInteractiveDoor) {
  // 13. WALK-IN NEIGHBORHOOD BUILDINGS AROUND THE SQUARE
  // 13a. Mrs. Miller's Cottage (№ 14 Maple Street — Garage, Corridor, Living, Kitchen, Bedroom, Toilet/Bath)
  placeInteractiveDoor({ id: 'miller_cottage', kind: 'front', axis: 'z', zw: 2196, open0: 226, y: ch1FloorY, swingDir: -1, startOpen: false, name: 'Коттедж миссис Миллер (дом № 14)' });
  placeInteractiveDoor({ id: 'miller_garage', kind: 'interior', axis: 'x', xw: 218, open0: 2208, y: ch1FloorY, swingDir: -1, startOpen: false, name: 'Гараж миссис Миллер' });
  placeInteractiveDoor({ id: 'miller_toilet', kind: 'interior', axis: 'x', xw: 218, open0: 2247, y: ch1FloorY, swingDir: -1, startOpen: false, name: 'Ванная и туалет (дом № 14)' });
  placeInteractiveDoor({ id: 'miller_bedroom', kind: 'interior', axis: 'z', zw: 2256, open0: 226, y: ch1FloorY, swingDir: -1, startOpen: false, name: 'Спальня миссис Миллер' });
  placeInteractiveDoor({ id: 'miller_living', kind: 'interior', axis: 'x', xw: 244, open0: 2208, y: ch1FloorY, swingDir: 1, startOpen: true, name: 'Гостиная (дом № 14)' });
  placeInteractiveDoor({ id: 'miller_kitchen', kind: 'interior', axis: 'x', xw: 244, open0: 2244, y: ch1FloorY, swingDir: 1, startOpen: false, name: 'Кухня (дом № 14)' });
  placeInteractiveDoor({ id: 'miller_dining', kind: 'interior', axis: 'z', zw: 2240, open0: 260, y: ch1FloorY, swingDir: -1, startOpen: true, name: 'Проход на кухню (дом № 14)' });
  // Miller Garage, Toilet/Bath, Corridor, Bedroom, Living, Kitchen props & per-room lighting
  G.place('car_sedan', m(203), ch1FloorY, m(2219), -Math.PI / 2, { mask: 3 });
  G.place('drawers', m(203), ch1FloorY, m(2242.5), Math.PI, { mask: 3 });
  G.place('bathtub', m(212), ch1FloorY, m(2270), 0, { mask: 3 });
  G.place('toilet', m(199), ch1FloorY, m(2275), Math.PI, { mask: 3 });
  G.place('washbasin', m(205), ch1FloorY, m(2250), 0, { mask: 3 });
  G.place('mirror_wall', m(220.2), ch1FloorY + 1.25, m(2230), Math.PI / 2, { mask: 3 });
  G.place('bed', m(234), ch1FloorY, m(2270), -Math.PI / 2, { mask: 3 });
  G.place('wardrobe', m(222.5), ch1FloorY, m(2268), Math.PI / 2, { mask: 3 });
  G.place('table', m(250), ch1FloorY, m(2226), 0, { mask: 3 });
  G.place('teapot', m(250.4), ch1FloorY + 0.64, m(2226), 0.2, { mask: 3, scale: 1.25 });
  G.place('teacup', m(249.5), ch1FloorY + 0.64, m(2226), -0.4, { mask: 3, scale: 1.3 });
  G.place('sofa', m(268), ch1FloorY, m(2210), 0, { mask: 3 });
  G.place('fireplace', m(251), ch1FloorY, m(2236), Math.PI, { mask: 3 });
  G.place('bookshelf', m(276), ch1FloorY, m(2236.5), Math.PI, { mask: 3 });
  G.place('kitchen_counter', m(280), ch1FloorY, m(2270), -Math.PI / 2, { mask: 3 });
  G.place('refrigerator', m(280), ch1FloorY, m(2250), -Math.PI / 2, { mask: 3 });
  G.place('table', m(256), ch1FloorY, m(2264), 0, { mask: 3 });
  G.place('chair', m(256), ch1FloorY, m(2271), Math.PI, { mask: 3 });
  G.light({ pos: [m(231), ch1FloorY + 3.3, m(2224)], r: 7.5, col: [1, 0.84, 0.6], k: 2.0, mask: 3 });
  G.light({ pos: [m(264), ch1FloorY + 3.3, m(2218)], r: 8.5, col: [1, 0.82, 0.56], k: 2.2, mask: 3 });
  G.light({ pos: [m(264), ch1FloorY + 3.3, m(2260)], r: 8.0, col: [1, 0.85, 0.62], k: 2.1, mask: 3 });
  G.light({ pos: [m(231), ch1FloorY + 3.3, m(2268)], r: 6.5, col: [1, 0.8, 0.55], k: 1.9, mask: 3 });
  G.light({ pos: [m(206), ch1FloorY + 3.3, m(2263)], r: 6.5, col: [0.92, 0.96, 1.0], k: 1.9, mask: 3 });
  G.light({ pos: [m(203), ch1FloorY + 3.3, m(2221)], r: 7.5, col: [0.92, 0.94, 0.98], k: 2.0, mask: 3 });

  // 13b. Professor Wagner's 2-Story Brick Manor (№ 18 Maple Street — 1F + 2F + Garage)
  placeInteractiveDoor({ id: 'wagner_study', kind: 'front', axis: 'z', zw: 2196, open0: 550, y: ch1FloorY, swingDir: -1, startOpen: false, name: 'Особняк профессора Вагнера (дом № 18)' });
  placeInteractiveDoor({ id: 'wagner_garage', kind: 'interior', axis: 'x', xw: 570, open0: 2201, y: ch1FloorY, swingDir: 1, startOpen: false, name: 'Гараж профессора Вагнера' });
  placeInteractiveDoor({ id: 'wagner_living', kind: 'interior', axis: 'z', zw: 2214, open0: 550, y: ch1FloorY, swingDir: -1, startOpen: true, name: 'Гостиная-кабинет (дом № 18)' });
  placeInteractiveDoor({ id: 'wagner_kitchen', kind: 'interior', axis: 'z', zw: 2248, open0: 526, y: ch1FloorY, swingDir: -1, startOpen: false, name: 'Кухня (дом № 18)' });
  placeInteractiveDoor({ id: 'wagner_toilet1', kind: 'interior', axis: 'z', zw: 2248, open0: 546, y: ch1FloorY, swingDir: -1, startOpen: false, name: 'Санузел 1-го этажа (дом № 18)' });
  placeInteractiveDoor({ id: 'wagner_bedroom', kind: 'interior', axis: 'x', xw: 546, open0: 2228, y: ch1Floor2Y, swingDir: -1, startOpen: false, name: 'Спальня профессора (2-й этаж № 18)' });
  placeInteractiveDoor({ id: 'wagner_bath2', kind: 'interior', axis: 'x', xw: 546, open0: 2258, y: ch1Floor2Y, swingDir: -1, startOpen: false, name: 'Ванная комната (2-й этаж № 18)' });
  placeInteractiveDoor({ id: 'wagner_library', kind: 'interior', axis: 'z', zw: 2226, open0: 552, y: ch1Floor2Y, swingDir: 1, startOpen: false, name: 'Верхняя библиотека (2-й этаж № 18)' });
  G.place('car_wagon', m(586), ch1FloorY, m(2224), -Math.PI / 2, { mask: 3 });
  G.place('workbench', m(586), ch1FloorY, m(2256), Math.PI, { mask: 3 });
  G.place('grandfather_clock', m(548), ch1FloorY, m(2200), 0, { mask: 3 });
  G.place('table', m(554), ch1FloorY, m(2226), 0, { mask: 3 });
  G.place('globe_stand', m(538), ch1FloorY, m(2226), 0.4, { mask: 3 });
  G.place('sofa', m(528), ch1FloorY, m(2206), 0, { mask: 3 });
  G.place('fireplace', m(519.2), ch1FloorY, m(2228), Math.PI / 2, { mask: 3 });
  G.place('bookshelf', m(567.2), ch1FloorY, m(2234), -Math.PI / 2, { mask: 3 });
  G.place('bookshelf', m(536), ch1FloorY, m(2245), Math.PI, { mask: 3 });
  G.place('kitchen_counter', m(520), ch1FloorY, m(2270), Math.PI / 2, { mask: 3 });
  G.place('refrigerator', m(520), ch1FloorY, m(2255), Math.PI / 2, { mask: 3 });
  G.place('table', m(534), ch1FloorY, m(2268), 0, { mask: 3 });
  G.place('chair', m(534), ch1FloorY, m(2261), 0, { mask: 3 });
  G.place('toilet', m(550), ch1FloorY, m(2275), Math.PI, { mask: 3 });
  G.place('washbasin', m(554), ch1FloorY, m(2262), -Math.PI / 2, { mask: 3 });
  // Wagner 2nd floor furniture
  G.place('bed', m(526), ch1Floor2Y, m(2220), Math.PI / 2, { mask: 3 });
  G.place('drawers', m(521), ch1Floor2Y, m(2201), 0, { mask: 3 });
  G.place('wardrobe', m(542), ch1Floor2Y, m(2208), -Math.PI / 2, { mask: 3 });
  G.place('bookshelf', m(567), ch1Floor2Y, m(2212), -Math.PI / 2, { mask: 3 });
  G.place('table', m(556), ch1Floor2Y, m(2206), 0, { mask: 3 });
  G.place('chair', m(556), ch1Floor2Y, m(2212), Math.PI, { mask: 3 });
  G.place('bathtub', m(521), ch1Floor2Y, m(2264), Math.PI / 2, { mask: 3 });
  G.place('toilet', m(540), ch1Floor2Y, m(2275), Math.PI, { mask: 3 });
  G.place('washbasin', m(530), ch1Floor2Y, m(2248), 0, { mask: 3 });
  G.light({ pos: [m(556), ch1FloorY + 3.3, m(2205)], r: 7.5, col: [1, 0.84, 0.58], k: 2.0, mask: 3 });
  G.light({ pos: [m(538), ch1FloorY + 3.3, m(2230)], r: 9.0, col: [1, 0.8, 0.52], k: 2.2, mask: 3 });
  G.light({ pos: [m(528), ch1FloorY + 3.3, m(2264)], r: 7.5, col: [1, 0.84, 0.6], k: 2.0, mask: 3 });
  G.light({ pos: [m(550), ch1FloorY + 3.3, m(2264)], r: 6.5, col: [0.92, 0.96, 1.0], k: 1.9, mask: 3 });
  G.light({ pos: [m(586), ch1FloorY + 3.3, m(2228)], r: 8.0, col: [0.92, 0.94, 0.98], k: 2.0, mask: 3 });
  G.light({ pos: [m(531), ch1Floor2Y + 2.8, m(2220)], r: 7.5, col: [1, 0.82, 0.56], k: 2.0, mask: 3 });
  G.light({ pos: [m(558), ch1Floor2Y + 2.8, m(2210)], r: 7.0, col: [1, 0.82, 0.56], k: 2.0, mask: 3 });
  G.light({ pos: [m(531), ch1Floor2Y + 2.8, m(2262)], r: 6.5, col: [0.92, 0.96, 1.0], k: 1.9, mask: 3 });

  // 13c. Apothecary Stern's Pharmacy & Attached Residence (№ 11 Maple Street)
  placeInteractiveDoor({ id: 'apothecary_shop', kind: 'front', axis: 'z', zw: 2098, open0: 236, y: ch1FloorY, swingDir: 1, startOpen: false, name: 'Городская аптека Штерна (дом № 11)' });
  placeInteractiveDoor({ id: 'apothecary_back_hall', kind: 'interior', axis: 'z', zw: 2052, open0: 236, y: ch1FloorY, swingDir: -1, startOpen: false, name: 'Жилая часть аптеки (коридор)' });
  placeInteractiveDoor({ id: 'apothecary_garage', kind: 'interior', axis: 'x', xw: 210, open0: 2062, y: ch1FloorY, swingDir: -1, startOpen: false, name: 'Гараж при аптеке № 11' });
  placeInteractiveDoor({ id: 'apothecary_living', kind: 'interior', axis: 'x', xw: 232, open0: 2038, y: ch1FloorY, swingDir: -1, startOpen: false, name: 'Гостиная (дом № 11)' });
  placeInteractiveDoor({ id: 'apothecary_bedroom', kind: 'interior', axis: 'x', xw: 232, open0: 2018, y: ch1FloorY, swingDir: -1, startOpen: false, name: 'Спальня (дом № 11)' });
  placeInteractiveDoor({ id: 'apothecary_kitchen', kind: 'interior', axis: 'x', xw: 248, open0: 2038, y: ch1FloorY, swingDir: 1, startOpen: false, name: 'Кухня (дом № 11)' });
  placeInteractiveDoor({ id: 'apothecary_toilet', kind: 'interior', axis: 'x', xw: 248, open0: 2018, y: ch1FloorY, swingDir: 1, startOpen: false, name: 'Санузел (дом № 11)' });
  G.place('car_sedan', m(198), ch1FloorY, m(2073), Math.PI / 2, { mask: 3 });
  G.place('apothecary_shelf', m(224), ch1FloorY, m(2055), 0, { mask: 3 });
  G.place('apothecary_shelf', m(256), ch1FloorY, m(2055), 0, { mask: 3 });
  G.place('table', m(240), ch1FloorY, m(2072), 0, { mask: 3 });
  G.place('sofa', m(214.5), ch1FloorY, m(2042), Math.PI / 2, { mask: 3 });
  G.place('table', m(223), ch1FloorY, m(2042), Math.PI / 2, { mask: 3 });
  G.place('bed', m(220), ch1FloorY, m(2021), Math.PI / 2, { mask: 3 });
  G.place('drawers', m(220), ch1FloorY, m(2016), 0, { mask: 3 });
  G.place('kitchen_counter', m(266), ch1FloorY, m(2043), -Math.PI / 2, { mask: 3 });
  G.place('refrigerator', m(266), ch1FloorY, m(2036), -Math.PI / 2, { mask: 3 });
  G.place('table', m(256), ch1FloorY, m(2042), 0, { mask: 3 });
  G.place('toilet', m(265), ch1FloorY, m(2016), 0, { mask: 3 });
  G.place('washbasin', m(258), ch1FloorY, m(2028), Math.PI, { mask: 3 });
  G.light({ pos: [m(240), ch1FloorY + 3.3, m(2075)], r: 8.5, col: [0.85, 0.96, 0.92], k: 2.2, mask: 3 });
  G.light({ pos: [m(240), ch1FloorY + 3.3, m(2032)], r: 6.5, col: [1, 0.85, 0.62], k: 1.9, mask: 3 });
  G.light({ pos: [m(221), ch1FloorY + 3.3, m(2042)], r: 6.5, col: [1, 0.82, 0.56], k: 1.9, mask: 3 });
  G.light({ pos: [m(221), ch1FloorY + 3.3, m(2022)], r: 6.5, col: [1, 0.8, 0.54], k: 1.9, mask: 3 });
  G.light({ pos: [m(259), ch1FloorY + 3.3, m(2042)], r: 6.5, col: [1, 0.86, 0.64], k: 1.9, mask: 3 });
  G.light({ pos: [m(259), ch1FloorY + 3.3, m(2022)], r: 6.0, col: [0.92, 0.96, 1.0], k: 1.8, mask: 3 });
  G.light({ pos: [m(198), ch1FloorY + 3.3, m(2072)], r: 7.5, col: [0.92, 0.94, 0.98], k: 2.0, mask: 3 });

  // 13d. University Cartography Exhibition Hall (x: 448..512, z: 2052..2094)
  placeInteractiveDoor({ id: 'uni_hall', kind: 'front', axis: 'z', zw: 2094, open0: 476, y: ch1FloorY, swingDir: 1, startOpen: false, name: 'Выставочный павильон Университета' });
  G.place('globe_stand', m(468), ch1FloorY, m(2072), 0.3, { mask: 3 });
  G.place('table', m(484), ch1FloorY, m(2072), 0, { mask: 3 });
  G.place('bookshelf', m(509.2), ch1FloorY, m(2064), -Math.PI / 2, { mask: 3 });
  G.place('bookshelf', m(509.2), ch1FloorY, m(2080), -Math.PI / 2, { mask: 3 });
  G.light({ pos: [m(480), ch1FloorY + 3.3, m(2072)], r: 9.5, col: [1, 0.86, 0.62], k: 2.2, mask: 3 });

  // 13e. Corner Bookshop & Photo Studio Residence (№ 15 Maple Street)
  placeInteractiveDoor({ id: 'bookshop_studio', kind: 'front', axis: 'z', zw: 2098, open0: 550, y: ch1FloorY, swingDir: 1, startOpen: false, name: 'Книжная лавка и фотоателье (дом № 15)' });
  placeInteractiveDoor({ id: 'bookshop_back_hall', kind: 'interior', axis: 'z', zw: 2052, open0: 550, y: ch1FloorY, swingDir: -1, startOpen: false, name: 'Жилая часть книжной лавки (коридор)' });
  placeInteractiveDoor({ id: 'bookshop_garage', kind: 'interior', axis: 'x', xw: 584, open0: 2056, y: ch1FloorY, swingDir: 1, startOpen: false, name: 'Гараж при доме № 15' });
  placeInteractiveDoor({ id: 'bookshop_living', kind: 'interior', axis: 'x', xw: 546, open0: 2038, y: ch1FloorY, swingDir: -1, startOpen: false, name: 'Гостиная (дом № 15)' });
  placeInteractiveDoor({ id: 'bookshop_bedroom', kind: 'interior', axis: 'x', xw: 546, open0: 2018, y: ch1FloorY, swingDir: -1, startOpen: false, name: 'Спальня (дом № 15)' });
  placeInteractiveDoor({ id: 'bookshop_kitchen', kind: 'interior', axis: 'x', xw: 562, open0: 2038, y: ch1FloorY, swingDir: 1, startOpen: false, name: 'Кухня (дом № 15)' });
  placeInteractiveDoor({ id: 'bookshop_toilet', kind: 'interior', axis: 'x', xw: 562, open0: 2018, y: ch1FloorY, swingDir: 1, startOpen: false, name: 'Санузел (дом № 15)' });
  G.place('car_wagon', m(597), ch1FloorY, m(2073), Math.PI / 2, { mask: 3 });
  G.place('bookshelf', m(538), ch1FloorY, m(2055), 0, { mask: 3 });
  G.place('bookshelf', m(570), ch1FloorY, m(2055), 0, { mask: 3 });
  G.place('bookshelf', m(581.2), ch1FloorY, m(2074), -Math.PI / 2, { mask: 3 });
  G.place('table', m(554), ch1FloorY, m(2074), 0, { mask: 3 });
  G.place('photo_enlarger', m(554), ch1FloorY + 0.64, m(2074), 0, { mask: 3 });
  G.place('sofa', m(530.5), ch1FloorY, m(2042), Math.PI / 2, { mask: 3 });
  G.place('table', m(538), ch1FloorY, m(2042), Math.PI / 2, { mask: 3 });
  G.place('bed', m(535), ch1FloorY, m(2021), Math.PI / 2, { mask: 3 });
  G.place('drawers', m(535), ch1FloorY, m(2016), 0, { mask: 3 });
  G.place('kitchen_counter', m(580), ch1FloorY, m(2043), -Math.PI / 2, { mask: 3 });
  G.place('refrigerator', m(580), ch1FloorY, m(2036), -Math.PI / 2, { mask: 3 });
  G.place('table', m(570), ch1FloorY, m(2042), 0, { mask: 3 });
  G.place('toilet', m(579), ch1FloorY, m(2016), 0, { mask: 3 });
  G.place('washbasin', m(572), ch1FloorY, m(2028), Math.PI, { mask: 3 });
  G.light({ pos: [m(554), ch1FloorY + 3.3, m(2074)], r: 8.5, col: [1, 0.82, 0.55], k: 2.2, mask: 3 });
  G.light({ pos: [m(554), ch1FloorY + 3.3, m(2032)], r: 6.5, col: [1, 0.85, 0.62], k: 1.9, mask: 3 });
  G.light({ pos: [m(536), ch1FloorY + 3.3, m(2042)], r: 6.5, col: [1, 0.82, 0.56], k: 1.9, mask: 3 });
  G.light({ pos: [m(536), ch1FloorY + 3.3, m(2022)], r: 6.5, col: [1, 0.8, 0.54], k: 1.9, mask: 3 });
  G.light({ pos: [m(572), ch1FloorY + 3.3, m(2042)], r: 6.5, col: [1, 0.86, 0.64], k: 1.9, mask: 3 });
  G.light({ pos: [m(572), ch1FloorY + 3.3, m(2022)], r: 6.0, col: [0.92, 0.96, 1.0], k: 1.8, mask: 3 });
  G.light({ pos: [m(597), ch1FloorY + 3.3, m(2072)], r: 7.5, col: [0.92, 0.94, 0.98], k: 2.0, mask: 3 });
}

// the mandatory clues of the chapter: desk, mirror, calendar, dresser, nightstand
function clueInteractions({ G, adapt, addClue, night, say, voice }, { ch1MirrorProp, ch1PassProp, ch1ReceiptProp, ch1SedativeProp }) {
  // --- INTERACTIONS: Chapter 1 ---

  // 1. Mandatory Desk: Answering Machine & Student Pass in Study
  G.interact({
    pos: [m(364), ch1FloorY + 0.7, m(2204)], r: 2.4, world: 'any',
    label: () => (!G.flags.ch1AnsweringHeard ? 'Стол в кабинете: прослушать автоответчик и забрать студенческий билет' : 'Стол Элиаса: прослушать запись автоответчика'),
    icon: 'sound', prop: ch1PassProp,
    cond: () => G.chapter === 1,
    run: async () => {
      G.audio.sfx('click');
      G.flags.ch1AnsweringHeard = true;
      addClue('c1_answering');
      voice('«Элиас, это Михаил! Выезжаем на перевал сегодня в ночь, иначе шторм размоют верхний карниз за два дня! Карты у меня в архиве... Хватит пить эти чертовы таблетки, тебе за руль садиться!»', 5.0, 'Автоответчик');
      await G.wait(4.8);
      G.audio.sfx('tick');
      voice('«Бип... бип... бип... Пульс нестабилен. Введите десять кубиков раствора...»', 4.0, 'Голос сквозь помехи');
      await G.wait(3.8);
      say(adapt({
        default: 'Странно… Сквозь голос Михаила на магнитной ленте пробивается ритмичный писк медицинского кардиомонитора.',
        TRUTH: 'Этот писк на фоне записи… Он звучит совсем как палата интенсивной терапии.',
        DENIAL: 'Просто радиопомехи на старой городской линии. Обычное осеннее утро.',
        PROJECTION: 'Почему Михаил так неистово торопил меня в ночь, прекрасно зная про шторм?',
      }), 4.2);
      if (!G.has('student_pass')) {
        await G.pickup('student_pass', { kicker: 'письменный стол в кабинете' });
        ch1PassProp.show(false);
      }
      if (!G.edits.ch1Door) {
        G.objective('Найти ключ от входной двери за зеркалом в прихожей и выйти наружу');
      }
    },
  });

  // 2. Hallway Mirror: Duality Reflection & Secret Key Box
  G.interact({
    pos: [m(393.4), ch1FloorY + 1.25, m(2201)], r: 2.3, world: 'any',
    label: () => (night() ? 'Зеркало в прихожей: вглядеться сквозь ледяную пелену' : 'Зеркало в прихожей: осмотреть отражение и раму'),
    icon: 'eye', prop: ch1MirrorProp,
    cond: () => G.chapter === 1,
    run: async () => {
      if (!night()) {
        G.audio.sfx('paper');
        say('В зеркале отражается синий вязаный свитер, но глаза впалые и чужие, словно я не спал целую вечность. На деревянной раме зеркала прикреплен секретный пенал для ключа, но замок словно заклинен сном. Вглядитесь глубже (R / Глаз)…', 4.8);
      } else {
        G.audio.sfx('water_in');
        addClue('c1_mirror');
        say('Стекло запотевает от чужого тяжелого дыхания. В глубине отражения проступает больничная койка, кислородной маска и синий браслет пациента на запястье с гравировкой «7319-Э». За рамой зеркала вспыхивает холодный металлический блеск!', 4.8);
        if (!G.has('apartment_key')) {
          await G.wait(1.5);
          if (await G.pickup('apartment_key', { kicker: 'тайник за зеркалом в прихожей' })) {
            say('Ключ от верхнего ригеля входной двери у меня! Теперь можно отпереть замок.', 3.8);
            if (!G.edits.ch1Door) {
              G.objective('Отпереть парадную дверь найденным ключом');
            }
          }
        }
      }
    },
  });

  // 3. Wall Calendar in 2nd-Floor Master Bedroom: Monday Oct 12 vs Intensive Care Red Marker
  G.interact({
    pos: [m(434), ch1Floor2Y + 1.38, m(2195.2)], r: 2.3, world: 'any',
    label: () => (night() ? 'Календарь на стене спальни (2-й этаж): прочитать водяные знаки в Кошмаре' : 'Календарь на стене спальни (2-й этаж): 12 октября (Понедельник)'),
    icon: 'read',
    cond: () => G.chapter === 1,
    run: async () => {
      G.audio.sfx('paper');
      addClue('c1_calendar');
      if (!night()) {
        await G.ui.read([
          '«ПОНЕДЕЛЬНИК, 12 ОКТЯБРЯ»',
          'Пометка карандашом: Собрать линзы, забрать у Михаила карты перевала. Выезд назначен на пятницу.',
        ], false, 'Календарь в спальне');
        say('На календаре понедельник… Но уголки страниц мокрые, словно их вытащили со дна реки.', 3.8);
      } else {
        await G.ui.read([
          '«ОТДЕЛЕНИЕ РЕАНИМАЦИИ И ИНТЕНСИВНОЙ ТЕРАПИИ № 7»',
          'Дата поступления: 18 октября. Травматический шок, аспирация речной водой.',
          'Пациент: Элиас В. Состояние: кома III степени. Выживших при падении автомобиля: 1(?).',
        ], true, 'Штамп приемного покоя');
        say('Дни недели перечеркнуты красным врачебным маркером… Неужели катастрофа уже случилась?!', 4.2);
      }
    },
  });

  // 4. Dresser in 2nd-Floor Master Bedroom: Auto repair brake receipt
  G.interact({
    pos: [m(427.2), ch1Floor2Y + 0.88, m(2216)], r: 2.3, world: 'any',
    label: 'Комод у стены спальни (2-й этаж): заказ-наряд автосервиса «Северный выезд»',
    icon: 'read', prop: ch1ReceiptProp,
    cond: () => G.chapter === 1 && !G.has('brake_receipt'),
    run: async () => {
      if (await G.pickup('brake_receipt', { kicker: 'комод в спальне (2-й этаж)' })) {
        ch1ReceiptProp.show(false);
        addClue('c1_brake_receipt');
        await G.ui.read([
          '«ЗАКАЗ-НАРЯД № 7319 · АВТОСЕРВИС СЕВЕРНЫЙ ВЫЕЗД»',
          'Автомобиль: Универсал Волга-2402 (синий). Владельцы: Элиас и Михаил.',
          'Диагностика: Критический износ тормозного контура заднего моста. Эксплуатация на горном серпантине запрещена.',
          'Особая отметка: Клиент от срочной замены отказался под личную расписку: „Мы спешим до грозы“...',
        ], false, 'Акт осмотра тормозов');
        say('Мастер запрещал нам выезжать на этом универсале в дождь… Но я настоял на своем.', 4.0);
      }
    },
  });

  // 5. Nightstand in 2nd-Floor Master Bedroom: Sedative Bottle
  G.interact({
    pos: [m(481.6), ch1Floor2Y + 0.88, m(2200)], r: 1.85, world: 'any',
    label: 'Прикроватная тумбочка у кровати (2-й этаж): осмотреть пузырёк с седативным',
    icon: 'hand', prop: ch1SedativeProp,
    cond: () => G.chapter === 1 && !G.has('sedative_bottle'),
    run: async () => {
      if (await G.pickup('sedative_bottle', { kicker: 'прикроватная тумбочка (2-й этаж)' })) {
        ch1SedativeProp.show(false);
        addClue('c1_sedative');
        say('Пузырёк сильного успокоительного… Доктор Арис предупреждал, что оно вызывает туман в голове и замедление реакций за рулем. Я выпил двойную дозу перед выездом.', 4.2);
      }
    },
  });
}

// optional things to examine inside the house: kitchen, bathroom, toilets, fireplace, darkroom
function roomInteractions({ G, addClue, night, say }, { ch1Cup }) {
  // 6. Cold teacup on the dining table in kitchen/dining
  G.interact({
    pos: [m(446), ch1FloorY + 0.7, m(2268)], r: 1.85, world: 'any',
    label: 'Обеденный стол в столовой: осмотреть чашку с остывшим чаем',
    icon: 'eye', prop: ch1Cup,
    cond: () => G.chapter === 1 && !G.memoryBoard.hasClue('c1_coffee_cup'),
    run: async () => {
      await G.inspect('teacup', 'Холодная фарфоровая чашка', 'На дне чашки застыл горький осадок седативного раствора, а от фарфора тянет холодом больничной палаты.', 'кухонный стол');
      addClue('c1_coffee_cup');
    },
  });

  // 6b. Kitchen Counter: Stove, Kettle and Sink
  G.interact({
    pos: [m(481.2), ch1FloorY + 0.85, m(2272)], r: 2.3, world: 'any',
    label: 'Кухонный гарнитур у стены: плита и мойка',
    icon: 'eye',
    cond: () => G.chapter === 1,
    run: async () => {
      if (!night()) {
        say('На плите чайник с сушёными травами. Пахнет мятой, чабрецом и пригоревшим металлом — словно конфорку забыли выключить в спешке перед ночной дорогой.', 4.2);
      } else {
        say('Из крана сочится ржавая речная вода, пахнущая тиной и донным илом. На кафеле проступают потеки, напоминающие контуры размытой горной трассы.', 4.2);
      }
    },
  });

  // 6c. Bathroom: Bathtub & Mirror Cabinet
  G.interact({
    pos: [m(340.2), ch1FloorY + 0.8, m(2276)], r: 2.3, world: 'any',
    label: () => (night() ? 'Ванная комната: вглядеться в воду чугунной ванны' : 'Ванная комната: осмотреть чугунную ванну и умывальник'),
    icon: 'eye',
    cond: () => G.chapter === 1,
    run: async () => {
      if (!night()) {
        say('Старая чугунная ванна на кованых лапах стоит вплотную у кафельной стены. Белый кафель чист, но в воздухе витает стойкий запах антисептика и спирта.', 4.0);
      } else {
        say('Ванна заполнена до краев ледяной илистой водой с плавающими опавшими листьями. В зеркале над раковиной на мгновение отражается стойка капельницы реанимационного бокса!', 4.5);
      }
    },
  });

  // 6c-2. Toilet #1 on Ground Floor (Powder Room)
  G.interact({
    pos: [m(340), ch1FloorY + 0.8, m(2250)], r: 2.2, world: 'any',
    label: 'Гостевой санузел первого этажа: осмотреть сантехнику',
    icon: 'eye',
    cond: () => G.chapter === 1,
    run: async () => {
      say('Белоснежный фарфоровый унитаз с хромированным рычагом слива и раковина на пьедестале у стены. Чистота безупречная.', 3.5);
    },
  });

  // 6c-3. Toilet #2 on Second Floor
  G.interact({
    pos: [m(414), ch1Floor2Y + 0.8, m(2198)], r: 2.2, world: 'any',
    label: 'Санузел второго этажа: осмотреть сантехнику',
    icon: 'eye',
    cond: () => G.chapter === 1,
    run: async () => {
      say('Просторный санузел второго этажа между спальнями. В бачке тихо шумит вода, на полочке над раковиной лежит свежее махровое полотенце.', 3.5);
    },
  });

  // 6c-4. Living Room Brick Fireplace
  G.interact({
    pos: [m(481), ch1FloorY + 1.0, m(2220)], r: 2.5, world: 'any',
    label: () => (night() ? 'Камин в гостиной: вглядеться в обугленные поленья' : 'Камин в гостиной: тлеющие дрова и резная полка'),
    icon: 'eye',
    cond: () => G.chapter === 1,
    run: async () => {
      if (!night()) {
        say('В кирпичном камине у восточной стены мягко потрескивают березовые дрова. На резной каминной полке стоят латунные подсвечники и черно-белые фотографии из наших студенческих экспедиций.', 4.5);
      } else {
        say('Огонь в камине вспыхивает тревожным мертвенно-синим пламенем. Из топки веет ледяным сквозняком горного ущелья, а среди углей виднеется оплавленный металл дверцы автомобиля!', 4.8);
      }
    },
  });

  // 6d. Basement Darkroom: Red Light & Wet Negatives
  G.interact({
    pos: [m(372), ch1BasementY + 0.85, m(2208.5)], r: 2.4, world: 'any',
    label: 'Подвал дома: домашняя фотолаборатория и фотоувеличитель',
    icon: 'eye',
    cond: () => G.chapter === 1,
    run: async () => {
      addClue('c1_darkroom_basement');
      G.audio.sfx('water_in');
      say('В просторном подвале под рубиновым светом фонаря покачиваются на бельевой веревке мокрые негативы. На снимках — серпантин Чертова каньона под проливным дождем. В кювете с фиксажем плавает отпечаток машины, зависшей над пропастью...', 5.0);
    },
  });
}

// porch, driveway, mailbox, clock, fridge, wardrobe, garage and basement workbenches
function yardInteractions({ G, addClue, night, say }, { ch1ClockProp, ch1FridgeProp }) {
  // 6e. Front Porch: Elias's Old Road Bicycle
  G.interact({
    pos: [m(394), ch1FloorY + 0.7, m(2189)], r: 2.1, world: 'any',
    label: 'Крыльцо: осмотреть дорожный велосипед',
    icon: 'eye',
    cond: () => G.chapter === 1,
    run: async () => {
      say('Мой старый дорожный велосипед с плетёной корзиной на руле. На цепи свежая смазка. До университета на нём всего десять минут неспешной езды по кленовой аллее. Зачем я согласился взять тяжелый универсал в ту грозовую полночь?..', 4.8);
    },
  });

  // 6f. Paved Driveway: Dark Oil & Brake Fluid Stain
  G.interact({
    pos: [m(316), ch1FloorY + 0.1, m(2188)], r: 1.85, world: 'any',
    label: () => (night() ? 'Подъездная дорожка: вглядеться в масляное пятно' : 'Подъездная дорожка перед гаражом: осмотреть пятно на плитах'),
    icon: 'eye',
    cond: () => G.chapter === 1,
    run: async () => {
      addClue('c1_oil_stain');
      if (!night()) {
        say('Растекшееся радужное пятно свежей тормозной жидкости и масла прямо на подъездной дорожке перед гаражом. Здесь стоял университетский универсал «Волга». Следы протектора ведут через ворота на шоссе…', 4.5);
      } else {
        say('Пятно кажется глубоким черным провалом. От него тянет гарью жженых колодок и ледяным холодом горного ущелья. Машина уехала отсюда с уже текущей тормозной системой.', 4.8);
      }
    },
  });

  // 6g. Mailbox at the Front Gate: Overdue Notices
  G.interact({
    pos: [m(398), ch1FloorY + 0.8, m(2178.5)], r: 1.85, world: 'any',
    label: 'Почтовый ящик у калитки: проверить почту',
    icon: 'read',
    cond: () => G.chapter === 1,
    run: async () => {
      addClue('c1_mailbox');
      G.audio.sfx('paper');
      await G.ui.read([
        '«СТРАХОВОЕ АГЕНТСТВО „СЕВЕРНЫЙ ВЫЕЗД“»',
        'Уведомление страхователю: Действие полиса автогражданской ответственности на синий универсал № 7319 приостановлено.',
        'Причина: Эксплуатация транспортного средства без прохождения обязательного сервисного ремонта тормозной магистрали.',
        'Пометка почтальона: „Вручить лично до 15 октября“...',
      ], false, 'Почтовый ящик у ворот');
      say('Страховка была аннулирована ещё до нашего выезда. Мы выехали на серпантин на свой страх и риск...', 4.2);
    },
  });

  // 6h. Grandfather Clock in 1st-Floor Hallway: Stopped at 01:17 AM
  let ch1ClockDayRead = false;
  let ch1ClockNightRead = false;
  G.interact({
    pos: [m(418), ch1FloorY + 1.1, m(2197)], r: 2.3, world: 'any',
    label: () => (night() ? 'Напольные часы: вглядеться в застывший маятник (01:17)' : 'Напольные часы у стены прихожей: проверить время и механизм'),
    icon: 'eye', prop: ch1ClockProp,
    cond: () => G.chapter === 1,
    run: async () => {
      G.audio.sfx('tick');
      addClue('c1_clock');
      if (!night()) {
        if (!ch1ClockDayRead) {
          ch1ClockDayRead = true;
          say('Старинные дубовые часы деда стоят у северной стены прихожей. Латунный маятник неподвижен, а стрелки замерли ровно на 01:17 ночи. Странно, почему они остановились, если сейчас солнечное утро понедельника?..', 4.5);
        } else {
          say('Часы замерли ровно на 01:17 ночи.', 2.2);
        }
      } else {
        if (!ch1ClockNightRead) {
          ch1ClockNightRead = true;
          say('В глубине застекленного корпуса вместо тиканья слышен глухой скрежет металла и плеск ледяной воды. 01:17 ночи — точное время, когда наш универсал сорвался с мокрого карниза над рекой!', 4.8);
        } else {
          say('01:17 ночи — время падения с карниза.', 2.4);
        }
      }
    },
  });

  // 6i. Refrigerator in Kitchen: Magnetic Note from Michael
  G.interact({
    pos: [m(480.8), ch1FloorY + 1.1, m(2254)], r: 2.3, world: 'any',
    label: 'Холодильник на кухне: прочитать записку под магнитом',
    icon: 'read', prop: ch1FridgeProp,
    cond: () => G.chapter === 1,
    run: async () => {
      G.audio.sfx('paper');
      addClue('c1_fridge_note');
      await G.ui.read([
        '«Элиас! Я положил в морозилку сухой паёк и термос для перевала.»',
        '«Прошу тебя: не бери с собой синие флаконы из аптеки Штерна и выспись перед дорогой.»',
        '«Если к вечеру четверга начнется шторм — перенесем выезд на субботу. Жизнь дороже диссертации. — М.»',
      ], false, 'Записка на дверце холодильника');
      say('Михаил оставил эту записку на холодильнике накануне отъезда… Он с самого начала готов был отложить экспедицию ради безопасности.', 4.4);
    },
  });

  // 6j. Master Bedroom Oak Wardrobe (flush against West wall x=424)
  G.interact({
    pos: [m(427.6), ch1Floor2Y + 1.1, m(2238)], r: 2.3, world: 'any',
    label: 'Платяной шкаф у стены спальни: осмотреть дорожную одежду',
    icon: 'eye',
    cond: () => G.chapter === 1,
    run: async () => {
      if (!night()) {
        say('В дубовом гардеробе у стены аккуратно висят теплые свитера и непромокаемый штормовой плащ. Но моего синего экспедиционного рюкзака на нижней полке уже нет — мы погрузили его в багажник универсала.', 4.2);
      } else {
        say('С вешалок капает ледяная речная вода. Ткань куртки распорота ножницами фельдшера скорой помощи, а в воздухе стоит тяжелый запах эфира и влажного ила.', 4.5);
      }
    },
  });

  // 6k. Garage Workbench & Tools (flush against South wall z=2262)
  G.interact({
    pos: [m(314), ch1FloorY + 0.9, m(2258.5)], r: 2.4, world: 'any',
    label: 'Гаражный верстак у стены: осмотреть инструменты и пустую канистру DOT-4',
    icon: 'eye',
    cond: () => G.chapter === 1,
    run: async () => {
      say('На массивном верстаке у южной стены гаража лежат гаечные ключи, монтировка и две пустые жестяные банки из-под тормозной жидкости. Я доливал её сам перед самым выездом вместо того, чтобы заменить лопнувшую трубку в автосервисе…', 4.6);
    },
  });

  // 6l. East Basement Storage & Boiler Room Workbench
  G.interact({
    pos: [m(440), ch1BasementY + 0.9, m(2208.5)], r: 2.4, world: 'any',
    label: 'Восточный отсек подвала: экспедиционное снаряжение и кофр',
    icon: 'eye',
    cond: () => G.chapter === 1,
    run: async () => {
      say('На стеллажах и верстаке вдоль каменной стены хранятся запасные штативы, алюминиевые тубусы для карт и старый кофр. На крышке ящика мелом написано рукой Михаила: «Проверить трос лебёдки и аптечку до выезда в Северный каньон».', 4.4);
    },
  });
}

// what the hero can examine in the walk-in buildings and on the square
function townInteractions({ G, addClue, night, say, voice }, { ch1ScarfProp }) {
  // 6m. Walk-in Building 1: Apothecary Stern's Pharmacy Counter (№ 11 Maple Street)
  G.interact({
    pos: [m(240), ch1FloorY + 0.9, m(2072)], r: 1.85, world: 'any',
    label: 'Прилавок аптеки Штерна (дом № 11): осмотреть рецептурный журнал',
    icon: 'read',
    cond: () => G.chapter === 1,
    run: async () => {
      G.audio.sfx('paper');
      addClue('c1_apothecary_ledger');
      await G.ui.read([
        '«ЖУРНАЛ УЧЁТА СИЛЬНОДЕЙСТВУЮЩИХ ПРЕПАРАТОВ · АПТЕКА ШТЕРНА»',
        'Запись № 418 от 14 октября: Пациент Элиас В. Препарат: „Сомнол-Форте“ (концентрат).',
        'Особое предупреждение фармацевта: КАТЕГОРИЧЕСКИ ЗАПРЕЩЕНО управление автотранспортом в течение 24 часов после приема.',
        'Подпись получателя об ознакомлении с риском потери концентрации за рулем: Элиас В.',
      ], false, 'Рецептурный журнал аптеки');
      say('Моя собственная подпись в аптечном журнале Штерна… Меня письменно предупреждали, что за руль после этих капель садиться смертельно опасно.', 4.5);
    },
  });

  // 6n. Walk-in Building 2: Professor Wagner's Cartography Study Table & Globe (№ 18 Maple Street)
  G.interact({
    pos: [m(554), ch1FloorY + 0.9, m(2226)], r: 1.85, world: 'any',
    label: 'Кабинет профессора Вагнера (дом № 18): осмотреть рельефную карту каньона',
    icon: 'read',
    cond: () => G.chapter === 1,
    run: async () => {
      G.audio.sfx('paper');
      addClue('c1_wagner_map');
      await G.ui.read([
        '«КАФЕДРА КАРТОГРАФИИ · ДОКЛАДНАЯ ЗАПИСКА ПРОФЕССОРА Г. ВАГНЕРА»',
        'Маршрутный лист студенческой группы (Элиас В., Михаил К.) по трассе Северного перевала.',
        'Резолюция от 15 октября: В связи со штормовым предупреждением метеослужбы и размывом глинистого карниза на 14-м километре ВЫЕЗД ЗАПРЕЩЁН.',
        'Примечание: Студент Михаил К. согласился перенести выезд, однако руководитель группы Элиас В. самовольно забрал ключи от экспедиционного универсала.',
      ], false, 'Штормовая сводка на карте Вагнера');
      say('Профессор Вагнер официально закрыл маршрут из-за оползня на 14-м километре. Михаил хотел остаться, а я забрал ключи и настоял на ночном выезде…', 4.6);
    },
  });

  // 6o. Walk-in Building 3: Mrs. Miller's Parlor Table (№ 14 Maple Street)
  G.interact({
    pos: [m(250), ch1FloorY + 0.9, m(2226)], r: 1.85, world: 'any',
    label: 'Гостиная миссис Миллер (дом № 14): чайный столик у окна на подъездную дорожку',
    icon: 'eye',
    cond: () => G.chapter === 1,
    run: async () => {
      say('Из восточного окна гостиной миссис Миллер как на ладони видна наша подъездная дорожка и гараж. На кружевной салфетке лежит её блокнот соседки-наблюдательницы: «Четверг, 23:40 — синий универсал уехал под проливным дождем. За рулем был Элиас, Михаил на пассажирском месте пытался его отговорить».', 5.0);
    },
  });

  // 6p. Walk-in Building 4: University Cartography Exhibition Hall Map Table
  G.interact({
    pos: [m(484), ch1FloorY + 0.9, m(2072)], r: 1.85, world: 'any',
    label: 'Выставочный павильон Университета: макет мостов Северного ущелья',
    icon: 'eye',
    cond: () => G.chapter === 1,
    run: async () => {
      say('Под стеклом выставочного стола в павильоне Университета — макет старого каменного моста над водопадом и старинный латунный глобус. Рядом табличка: «Экспозиция подготовлена Элиасом и Михаилом». В режиме Кошмара на макете видна черная трещина обрыва…', 4.6);
    },
  });

  // 8. Telephone Booth on South Sidewalk: Recorded Emergency Call
  G.interact({
    pos: [m(422), ch1FloorY + 1.2, m(2178)], r: 1.85, world: 'any',
    label: () => (night() ? 'Телефонная будка: вглядеться в тень у трубки' : 'Телефонная будка: поднять свисающую трубку'),
    icon: 'sound',
    cond: () => G.chapter === 1,
    run: async () => {
      G.audio.sfx('click');
      addClue('c1_phone_record');
      voice('«Гудки... Щелчок коммутатора...»', 2.5, 'Телефонная линия');
      await G.wait(2.2);
      voice('«„Алло, оператор МЧС?! Это Михаил... Мы на развилке Северного тракта! Мой напарник сошел с ума, он гонит машину в ночной шторм, а у нас текут тормоза! Скажите ему, что мост перекрыт, умоляю вас, иначе мы разобьемся!..“»', 5.5, 'Запись звонка');
      await G.wait(5.2);
      say('Трубка замолкла. Михаил действительно звонил спасателям той ночью... Он пытался остановить меня.', 4.2);
    },
  });

  // 9. University Notice Board: Expedition vs MChS Search Bulletin
  G.interact({
    pos: [m(406), ch1FloorY + 1.2, m(2098)], r: 1.85, world: 'any',
    label: () => (night() ? 'Стенд объявлений: читать ориентировку поискового отряда' : 'Информационный стенд Университета: объявление экспедиции'),
    icon: 'read',
    cond: () => G.chapter === 1,
    run: async () => {
      G.audio.sfx('paper');
      addClue('c1_bulletin');
      if (!night()) {
        await G.ui.read([
          '«КАФЕДРА КАРТОГРАФИИ И ТОПОГРАФИИ»',
          'Студенческая научно-исследовательская экспедиция в Северный каньон.',
          'Руководители группы: Элиас В. и Михаил К.',
          'Цель: аэрофотосъемка древних мостовых переправ и геологический очерк.',
        ], false, 'Объявление на кафедре');
        say('Мы так долго мечтали об этой поездке... Готовились к ней целый год.', 3.5);
      } else {
        await G.ui.read([
          '«ОРИЕНТИРОВКА ПОИСКОВО-СПАСАТЕЛЬНОЙ СЛУЖБЫ»',
          'Чрезвычайное происшествие на 14-м километре горного серпантина.',
          'Синий универсал Волга-2402 (госномер 7319) пробил ограждение и затонул в реке.',
          'Один пострадавший доставлен в реанимацию в критическом состоянии. Поиски на реке продолжаются.',
        ], true, 'Сводка МЧС');
        say('Это сводка о нашей машине… Дата совпадает с той субботней ночью.', 4.0);
      }
    },
  });

  // 10. Park Bench on Central Neighborhood Square: Leah's Scarf
  G.interact({
    pos: [m(406), ch1FloorY + 0.6, m(2144)], r: 1.85, world: 'any',
    label: 'Скамья в сквере: поднять изумрудный шарф Лии',
    icon: 'hand', prop: ch1ScarfProp,
    cond: () => G.chapter === 1 && !G.has('leah_scarf'),
    run: async () => {
      if (await G.pickup('leah_scarf', { kicker: 'скамья в сквере на площади' })) {
        ch1ScarfProp.show(false);
        addClue('c1_scarf');
        voice('«„Элиас, ты всегда думаешь только о своих снимках и признании! Не уезжайте в эту бурю… у меня дурное предчувствие…“»', 4.5, 'Голос Лии');
        await G.wait(4.2);
        say('Шарф Лии. Она сидела на этой скамье в сквере и плакала перед нашим отъездом…', 3.8);
      }
    },
  });

  // 14. Street Vehicle 1: Parked Blue Sedan
  G.interact({
    pos: [m(352), ch1FloorY + 0.8, m(2171)], r: 1.85, world: 'any',
    label: 'Осмотреть припаркованный синий седан соседа',
    icon: 'eye',
    cond: () => G.chapter === 1,
    run: async () => {
      G.audio.sfx('click');
      say('Полноразмерный синий седан соседа с хромированными бамперами. На лобовом стекле капли утренней росы. На обочине пахнет сырой землей и осенними листьями.', 4.0);
    },
  });

  // 15. Street Vehicle 2: Station Wagon on North Curb
  G.interact({
    pos: [m(452), ch1FloorY + 0.8, m(2158)], r: 1.85, world: 'any',
    label: 'Осмотреть грузопассажирский универсал у сквера',
    icon: 'eye',
    cond: () => G.chapter === 1,
    run: async () => {
      G.audio.sfx('click');
      say('Крупный грузопассажирский универсал с багажником на крыше. Модель почти такая же, как наш экспедиционный автомобиль... Но этот целый и сухой, без вмятин от камней и воды.', 4.5);
    },
  });

  // 16. Municipal Fire Hydrant on South Sidewalk
  G.interact({
    pos: [m(386), ch1FloorY + 0.6, m(2177.5)], r: 1.85, world: 'any',
    label: 'Осмотреть чугунный пожарный гидрант',
    icon: 'eye',
    cond: () => G.chapter === 1,
    run: async () => {
      G.audio.sfx('click');
      say('Красный чугунный гидрант муниципальной службы на краю бетонного тротуара. На литом корпусе видна дата отливки — 1974 год.', 3.8);
    },
  });
}

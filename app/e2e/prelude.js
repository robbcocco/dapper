// Evaluated (debug builds only) before every scenario; see src-tauri/src/e2e.rs.
// Scenario bodies run inside an async function with these helpers in scope via `__e2e`.
window.__e2e = (() => {
  const T = window.__TAURI_INTERNALS__;
  const emit = (event, payload) => T.invoke('plugin:event|emit', { event, payload }).catch(() => {});
  const log = (msg) => emit('e2e:log', String(msg));
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let failures = 0;
  let shotResolve = null;
  let shResolve = null;

  /** Runs `cmd` on the host via `sh -c`; resolves `{ code, out }`. One at a time. */
  function sh(cmd) {
    return new Promise((r) => {
      shResolve = r;
      emit('e2e:sh', cmd);
    });
  }

  const visible = (el) => !!el && el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
  const textOf = (el) => (el.innerText ?? el.textContent ?? '').replace(/\s+/g, ' ').trim();
  const matches = (el, text) =>
    text === undefined ? true : text instanceof RegExp ? text.test(textOf(el)) : textOf(el).includes(text);

  /** All visible elements matching `sel` (and `text`, substring or RegExp). */
  function all(sel, opts = {}) {
    const root = opts.within ? (typeof opts.within === 'string' ? document.querySelector(opts.within) : opts.within) : document;
    if (!root) return [];
    return [...root.querySelectorAll(sel)].filter((el) => (opts.hidden || visible(el)) && matches(el, opts.text));
  }
  const find = (sel, opts) => all(sel, opts)[0] ?? null;

  async function waitFor(sel, opts = {}) {
    const timeout = opts.timeout ?? 10000;
    const until = Date.now() + timeout;
    for (;;) {
      const el = find(sel, opts);
      if (opts.gone ? !el : el) return el;
      if (Date.now() > until) {
        const what = `${sel}${opts.text !== undefined ? ` text=${opts.text}` : ''}`;
        throw new Error(`${opts.gone ? 'still present' : 'not found'} after ${timeout}ms: ${what}`);
      }
      await sleep(100);
    }
  }

  async function until(pred, desc, timeout = 10000) {
    const end = Date.now() + timeout;
    for (;;) {
      const v = await pred();
      if (v) return v;
      if (Date.now() > end) throw new Error(`timed out: ${desc}`);
      await sleep(150);
    }
  }

  const resolve = async (target, opts) => (typeof target === 'string' ? waitFor(target, opts) : target);

  function mouse(el, type, extra = {}) {
    const r = el.getBoundingClientRect();
    const init = { bubbles: true, cancelable: true, composed: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2, button: extra.button ?? 0, ...extra };
    const Ctor = type.startsWith('pointer') ? PointerEvent : MouseEvent;
    return el.dispatchEvent(new Ctor(type, { pointerId: 1, isPrimary: true, ...init }));
  }

  async function click(target, opts = {}) {
    const el = await resolve(target, opts);
    el.scrollIntoView({ block: 'nearest' });
    for (const t of ['pointerdown', 'mousedown', 'pointerup', 'mouseup']) mouse(el, t, opts.mouse);
    if (opts.mouse?.detail === 2 || opts.double) {
      el.click();
      mouse(el, 'click', { detail: 1, ...opts.mouse });
      mouse(el, 'dblclick', { detail: 2, ...opts.mouse });
    } else {
      mouse(el, 'click', { detail: 1, ...opts.mouse });
    }
    await sleep(opts.settle ?? 150);
    return el;
  }
  const dblclick = (target, opts = {}) => click(target, { ...opts, double: true });

  /** Context menus are native; scenarios pre-select an item label (or null to dismiss). */
  let menuPick = null;
  let lastMenu = null;
  window.__e2eMenu = async (items) => {
    lastMenu = items;
    const flat = (xs) => xs.flatMap((i) => ('separator' in i ? [] : [i, ...(i.submenu ? flat(i.submenu) : [])]));
    const pick = menuPick;
    menuPick = null;
    if (pick === null) return null;
    const it = flat(items).find((i) => (pick instanceof RegExp ? pick.test(i.label) : i.label === pick));
    if (!it) {
      log(`menu: no item ${pick} in [${flat(items).map((i) => i.label).join(' | ')}]`);
      return null;
    }
    return it.id;
  };
  async function contextMenu(target, label, opts = {}) {
    const el = await resolve(target, opts);
    el.scrollIntoView({ block: 'nearest' });
    menuPick = label;
    lastMenu = null;
    mouse(el, 'contextmenu', { button: 2 });
    await until(() => lastMenu, `context menu on ${typeof target === 'string' ? target : el.tagName}`, 5000);
    await sleep(opts.settle ?? 250);
    return lastMenu;
  }

  async function type(target, text, opts = {}) {
    const el = await resolve(target, opts);
    el.focus();
    const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, text);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    await sleep(opts.settle ?? 100);
    return el;
  }

  async function key(k, opts = {}) {
    const el = opts.target ? await resolve(opts.target) : document.activeElement ?? document.body;
    const init = { key: k, code: opts.code ?? k, bubbles: true, cancelable: true, metaKey: !!opts.meta, shiftKey: !!opts.shift, ctrlKey: !!opts.ctrl, altKey: !!opts.alt };
    el.dispatchEvent(new KeyboardEvent('keydown', init));
    el.dispatchEvent(new KeyboardEvent('keyup', init));
    await sleep(opts.settle ?? 150);
  }

  function shot(name) {
    return new Promise((r) => {
      const t = setTimeout(r, 8000);
      shotResolve = () => {
        clearTimeout(t);
        r();
      };
      // Let the frame settle before the capture.
      requestAnimationFrame(() => setTimeout(() => emit('e2e:shot', name), 250));
    });
  }

  async function step(name, fn) {
    const t0 = Date.now();
    try {
      await fn();
      log(`PASS ${name} (${Date.now() - t0}ms)`);
      return true;
    } catch (e) {
      failures++;
      log(`FAIL ${name}: ${e?.message ?? e}`);
      await shot(`FAIL-${name.replace(/[^\w-]+/g, '_')}`);
      return false;
    }
  }

  function assert(cond, msg) {
    if (!cond) throw new Error(`assert: ${msg}`);
  }

  /** The input inside the TextField/SecretField whose label is `label`. */
  async function field(label, opts = {}) {
    const tf = await waitFor('label', { ...opts, text: new RegExp(`^${label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`) });
    const input = tf.querySelector('input, textarea');
    if (!input) throw new Error(`no input under label ${label}`);
    return input;
  }

  /** Logs a compact tag.class outline of `sel` (exploration aid). */
  function dump(sel = 'body', depth = 6) {
    const root = typeof sel === 'string' ? document.querySelector(sel) : sel;
    const out = [];
    const walk = (el, d) => {
      if (!visible(el) || d > depth) return;
      const cls = typeof el.className === 'string' && el.className ? '.' + el.className.trim().split(/\s+/).filter((c) => !c.startsWith('svelte-')).join('.') : '';
      const own = [...el.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent.trim()).join(' ').slice(0, 40);
      out.push(`${'  '.repeat(d)}${el.tagName.toLowerCase()}${cls}${el.getAttribute('aria-label') ? `[${el.getAttribute('aria-label')}]` : ''}${own ? ` "${own}"` : ''}`);
      [...el.children].slice(0, 12).forEach((c) => walk(c, d + 1));
    };
    if (root) walk(root, 0);
    log(`dump ${typeof sel === 'string' ? sel : root?.tagName}:\n${out.join('\n')}`);
  }

  /** Scrolls `scroller` (selector) top→bottom until `sel`/`opts.text` renders (virtual lists). */
  async function scrollFind(scroller, sel, opts = {}) {
    const sc = await resolve(scroller);
    sc.scrollTop = 0;
    await sleep(200);
    for (;;) {
      const el = find(sel, opts);
      if (el) {
        el.scrollIntoView({ block: 'center' });
        await sleep(200);
        return find(sel, opts);
      }
      if (sc.scrollTop + sc.clientHeight >= sc.scrollHeight - 1) throw new Error(`scrolled to end: ${sel} text=${opts.text}`);
      sc.scrollTop += sc.clientHeight * 0.8;
      await sleep(250);
    }
  }

  /** Picks the option whose label is `label` in a native <select>. */
  async function choose(target, label, opts = {}) {
    const el = await resolve(target, opts);
    const i = [...el.options].findIndex((o) => o.text.trim() === label);
    if (i < 0) throw new Error(`no option ${label} in [${[...el.options].map((o) => o.text).join('|')}]`);
    el.selectedIndex = i;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    await sleep(opts.settle ?? 300);
    return el;
  }

  const invoke = (cmd, args) => T.invoke(cmd, args);

  /** Setup screen → demo server → shell; waits for the first library sync to finish. */
  async function connectDemo() {
    await waitFor('form.card', { text: 'Connect to Navidrome', timeout: 20000 });
    await type(await field('Server URL'), 'https://demo.navidrome.org');
    await type(await field('Username'), 'demo');
    await type(await field('Password'), 'demo');
    await click('button[type=submit]', { text: 'Connect' });
    await waitFor('nav.sidebar', { timeout: 30000 });
    await waitForSync();
  }

  async function waitForSync(timeout = 180000) {
    await sleep(500);
    return until(async () => {
      const s = await invoke('library_sync_status');
      if (s.error) throw new Error(`library sync error: ${s.error}`);
      return !s.running && s.lastSyncedAt ? s : null;
    }, 'library sync', timeout);
  }

  // Toasts and backend action errors are surfaced in the log for diagnosis.
  T.invoke('plugin:event|listen', {
    event: 'action-error',
    target: { kind: 'Any' },
    handler: T.transformCallback((e) => log(`action-error: ${e.payload?.message}`)),
  }).catch(() => {});
  window.addEventListener('error', (e) => log(`window.error: ${e.message}\n${e.error?.stack ?? ''}`));
  for (const level of ['error', 'warn']) {
    const orig = console[level].bind(console);
    console[level] = (...args) => {
      orig(...args);
      log(`console.${level}: ${args.map((a) => (a instanceof Error ? a.stack : typeof a === 'object' ? JSON.stringify(a) : String(a))).join(' ').slice(0, 2000)}`);
    };
  }
  window.addEventListener('unhandledrejection', (e) => log(`unhandledrejection: ${e.reason?.message ?? JSON.stringify(e.reason)}`));

  return {
    log, sleep, all, find, waitFor, until, click, dblclick, contextMenu, type, key, shot, step, assert, textOf, field, dump, choose, scrollFind, invoke, connectDemo, waitForSync, sh,
    get failures() {
      return failures;
    },
    shotDone: () => shotResolve?.(),
    shDone: (res) => shResolve?.(res),
    done: () => {
      log(`DONE failures=${failures}`);
      emit('e2e:exit', failures ? 1 : 0);
    },
    crash: (e) => {
      log(`FAIL script crashed: ${e?.stack ?? e}`);
      emit('e2e:exit', 2);
    },
  };
})();
const { log, sleep, all, find, waitFor, until, click, dblclick, contextMenu, type, key, shot, step, assert, textOf, field, dump, choose, scrollFind, invoke, connectDemo, waitForSync, sh } = window.__e2e;

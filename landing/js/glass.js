/* =========================================================
   Liquid glass (for every .glass element; styles in css/style.css)
   ---------------------------------------------------------
   1. Refraction (Chromium: Chrome, Edge, Opera, Samsung Internet)
      Each element gets its own SVG filter, used through backdrop-filter.
      The filter displaces the real backdrop with a map computed from the
      element's exact shape: inside a curved bezel along the edge, pixels are
      sampled from further in (like a thick convex lens), strongest at the
      edge and fading to zero, so the middle stays clear. Red, green and blue
      are displaced by slightly different amounts for a faint chromatic
      fringe. The map is rebuilt only when the element's size changes.
      Safari and Firefox can't use an SVG filter in backdrop-filter, so there
      the glass keeps the CSS fallback: softer blur with the same lighting.
   2. Lighting
      The rim and the specular reflection turn toward the pointer, following
      it through a spring (never snapping), and settle back to light from
      the top-left when the pointer leaves. Glass that moves (the brand)
      re-aims its light while the page scrolls. The loop stops once settled.
   ========================================================= */
(() => {
    const SVG_NS = 'http://www.w3.org/2000/svg';
    const MAP_RES = 0.5;       // displacement-map pixels per CSS pixel (the field is smooth)
    const BEND_POWER = 1.6;    // lens profile falloff; lower = more domed edge
    const REACH = 700;         // px; how far from the pointer the glass still reacts
    const SPRING = 120;        // stiffness
    const DAMPING = 19;        // a bit under critical: settles with a barely-there overshoot
    const DEFAULT_LIGHT = { dx: Math.SQRT1_2, dy: Math.SQRT1_2, lx: 18, ly: -10 };  // from top-left

    const glasses = [...document.querySelectorAll('.glass')];
    if (!glasses.length) return;

    // Engine check rather than @supports: Safari parses url() in backdrop-filter
    // but doesn't render it, so feature detection would wrongly pass there.
    const canRefract = !!(navigator.userAgentData &&
        navigator.userAgentData.brands.some((b) => b.brand === 'Chromium'));
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const defs = document.querySelector('.svg-defs defs');

    const clamp = (v, min = 0, max = 1) => Math.min(max, Math.max(min, v));
    const cssNum = (style, name, fallback) => {
        const v = parseFloat(style.getPropertyValue(name));
        return Number.isNaN(v) ? fallback : v;
    };

    /* ---------- Refraction ---------- */

    let filterCount = 0;

    // Displacement map for a w x h rounded rectangle with corner radius r and a
    // curved bezel of width `bezel`. Red = x shift, green = y shift, 128 = none.
    function lensMap(w, h, r, bezel) {
        const mw = Math.max(2, Math.round(w * MAP_RES));
        const mh = Math.max(2, Math.round(h * MAP_RES));
        const canvas = document.createElement('canvas');
        canvas.width = mw;
        canvas.height = mh;
        const ctx = canvas.getContext('2d');
        const img = ctx.createImageData(mw, mh);
        const data = img.data;
        const hw = w / 2;
        const hh = h / 2;

        for (let y = 0; y < mh; y++) {
            for (let x = 0; x < mw; x++) {
                // Position from the center; the shape is symmetric, so work in |x|, |y|
                const ax = (x + 0.5) / MAP_RES - hw;
                const ay = (y + 0.5) / MAP_RES - hh;
                const qx = Math.abs(ax) - (hw - r);
                const qy = Math.abs(ay) - (hh - r);

                // t = distance in from the edge; (nx, ny) = outward surface normal
                let t;
                let nx = 0;
                let ny = 0;
                if (qx > 0 && qy > 0) {            // rounded corner
                    const l = Math.hypot(qx, qy) || 1;
                    t = r - l;
                    nx = qx / l;
                    ny = qy / l;
                } else if (qx > qy) {              // left / right edge
                    t = r - qx;
                    nx = 1;
                } else {                           // top / bottom edge
                    t = r - qy;
                    ny = 1;
                }

                // Lens profile: full bend at the edge, easing to none at the bezel's inner side.
                // A power below 2 keeps the bend further in, so the edge reads as more domed.
                const u = clamp(t / bezel);
                const bend = t < 0 ? 0 : Math.pow(1 - u, BEND_POWER);

                // Sample from further inside: opposite the outward normal
                const dx = -nx * Math.sign(ax) * bend;
                const dy = -ny * Math.sign(ay) * bend;

                const i = (y * mw + x) * 4;
                data[i] = 128 + dx * 127;
                data[i + 1] = 128 + dy * 127;
                data[i + 2] = 128;
                data[i + 3] = 255;
            }
        }
        ctx.putImageData(img, 0, 0);
        return canvas.toDataURL();
    }

    function svgEl(tag, attrs) {
        const node = document.createElementNS(SVG_NS, tag);
        for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
        return node;
    }

    // Keep only one color channel of a displaced copy
    const CHANNEL = {
        r: '1 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 1 0',
        g: '0 0 0 0 0  0 1 0 0 0  0 0 0 0 0  0 0 0 1 0',
        b: '0 0 0 0 0  0 0 0 0 0  0 0 1 0 0  0 0 0 1 0',
    };

    // feImage(map) -> displace the backdrop; with chroma, red / green / blue
    // are displaced by slightly different amounts and added back together
    function buildFilter(id, w, h, map, scale, chroma) {
        const filter = svgEl('filter', {
            id, x: 0, y: 0, width: w, height: h,
            filterUnits: 'userSpaceOnUse',
            'color-interpolation-filters': 'sRGB',
        });
        filter.append(svgEl('feImage', {
            href: map, x: 0, y: 0, width: w, height: h,
            preserveAspectRatio: 'none', result: 'map',
        }));

        const displace = (s, result) => svgEl('feDisplacementMap', {
            in: 'SourceGraphic', in2: 'map', scale: s,
            xChannelSelector: 'R', yChannelSelector: 'G', result,
        });

        if (chroma < 0.005) {
            filter.append(displace(scale, 'out'));
            return filter;
        }

        [['r', 1 - chroma], ['g', 1], ['b', 1 + chroma]].forEach(([c, k]) => {
            filter.append(displace(scale * k, `d${c}`));
            filter.append(svgEl('feColorMatrix', { in: `d${c}`, type: 'matrix', values: CHANNEL[c], result: c }));
        });
        filter.append(svgEl('feComposite', { in: 'r', in2: 'g', operator: 'arithmetic', k2: 1, k3: 1, result: 'rg' }));
        filter.append(svgEl('feComposite', { in: 'rg', in2: 'b', operator: 'arithmetic', k2: 1, k3: 1 }));
        return filter;
    }

    // (Re)build an element's filter for its current size
    function refract(g) {
        const w = g.el.offsetWidth;
        const h = g.el.offsetHeight;
        if (!w || !h || (w === g.w && h === g.h)) return;
        g.w = w;
        g.h = h;

        const style = getComputedStyle(g.el);
        const r = Math.min(parseFloat(style.borderTopLeftRadius) || 0, w / 2, h / 2);
        const bezel = Math.min(cssNum(style, '--glass-bezel', 38), w / 2, h / 2);
        const scale = cssNum(style, '--glass-refraction', 42) * 2;  // map spans -0.5..0.5
        const chroma = cssNum(style, '--glass-chroma', 0.1);

        // A fresh id each time, so no browser serves a cached result for the old size
        const id = `glass-filter-${++filterCount}`;
        const filter = buildFilter(id, w, h, lensMap(w, h, r, bezel), scale, chroma);
        defs.append(filter);
        g.el.style.setProperty('--glass-filter', `url(#${id})`);
        g.el.classList.add('is-refracting');
        if (g.filter) g.filter.remove();
        g.filter = filter;
    }

    /* ---------- Lighting ---------- */

    // Light state per element: direction (dx, dy) and specular spot (lx, ly in %),
    // each with a velocity for the spring
    const items = glasses.map((el) => ({
        el,
        w: 0,
        h: 0,
        filter: null,
        interaction: cssNum(getComputedStyle(el), '--glass-interaction', 1),
        cur: { ...DEFAULT_LIGHT },
        vel: { dx: 0, dy: 0, lx: 0, ly: 0 },
    }));

    let pointer = null;
    let running = false;
    let last = 0;

    function target(g) {
        if (!pointer) return DEFAULT_LIGHT;
        const rect = g.el.getBoundingClientRect();
        const cx = rect.left + rect.width / 2;
        const cy = rect.top + rect.height / 2;
        const vx = cx - pointer.x;
        const vy = cy - pointer.y;
        const dist = Math.hypot(vx, vy) || 1;
        const k = g.interaction * clamp(1 - dist / REACH);

        // Blend the default light direction toward "from the pointer", then normalize
        let dx = DEFAULT_LIGHT.dx + (vx / dist - DEFAULT_LIGHT.dx) * k;
        let dy = DEFAULT_LIGHT.dy + (vy / dist - DEFAULT_LIGHT.dy) * k;
        const l = Math.hypot(dx, dy) || 1;
        dx /= l;
        dy /= l;

        const px = clamp(((pointer.x - rect.left) / rect.width) * 100, -30, 130);
        const py = clamp(((pointer.y - rect.top) / rect.height) * 100, -30, 130);
        return {
            dx,
            dy,
            lx: DEFAULT_LIGHT.lx + (px - DEFAULT_LIGHT.lx) * k,
            ly: DEFAULT_LIGHT.ly + (py - DEFAULT_LIGHT.ly) * k,
        };
    }

    function tick(now) {
        const dt = Math.min(0.032, (now - last) / 1000 || 0.016);
        last = now;
        let moving = false;

        items.forEach((g) => {
            const t = target(g);
            for (const key of ['dx', 'dy', 'lx', 'ly']) {
                const scale = key === 'lx' || key === 'ly' ? 0.01 : 1;  // % values: compare in 0-1 range
                const a = SPRING * (t[key] - g.cur[key]) - DAMPING * g.vel[key];
                g.vel[key] += a * dt;
                g.cur[key] += g.vel[key] * dt;
                if (Math.abs(t[key] - g.cur[key]) * scale > 0.001 || Math.abs(g.vel[key]) * scale > 0.001) moving = true;
            }
            // Rim gradient angle: CSS 0deg = up; the gradient starts on the lit side
            const angle = Math.atan2(g.cur.dx, -g.cur.dy) * 180 / Math.PI;
            g.el.style.setProperty('--glass-la', `${angle.toFixed(1)}deg`);
            g.el.style.setProperty('--glass-lx', `${g.cur.lx.toFixed(1)}%`);
            g.el.style.setProperty('--glass-ly', `${g.cur.ly.toFixed(1)}%`);
        });

        if (moving) {
            requestAnimationFrame(tick);
        } else {
            running = false;
        }
    }

    function start() {
        if (running) return;
        running = true;
        last = performance.now();
        requestAnimationFrame(tick);
    }

    /* ---------- Setup ---------- */

    if (canRefract) {
        const ro = new ResizeObserver((entries) => {
            entries.forEach((entry) => refract(items.find((g) => g.el === entry.target)));
        });
        items.forEach((g) => {
            refract(g);
            ro.observe(g.el);
        });
    }

    if (!reduceMotion) {
        window.addEventListener('scroll', () => { if (pointer) start(); }, { passive: true });
        window.addEventListener('pointermove', (e) => {
            pointer = { x: e.clientX, y: e.clientY };
            start();
        }, { passive: true });
        document.documentElement.addEventListener('pointerleave', () => {
            pointer = null;
            start();
        });
    }
})();

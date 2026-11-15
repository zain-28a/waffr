/* =========================================================
   Waffr landing page: scroll motion
   - Brand (logo + slogan, liquid glass): flies from its place on the
     cover to the top-left corner and stays there.
   - Ambient lights: move with scroll and blend their colors section by
     section (data-tone on each section).
   - Cover card eases back slightly as you leave it.
   - Reveal on view, rules that draw in, figures that count up,
     posts that tilt toward the pointer and open full size.
   ========================================================= */
(() => {
    const root = document.documentElement;
    root.classList.remove('no-js');
    root.classList.add('js');

    const $ = (s, el = document) => el.querySelector(s);
    const $$ = (s, el = document) => [...el.querySelectorAll(s)];
    const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
    const lerp = (a, b, t) => a + (b - a) * t;
    const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
    const easeOut = (t) => 1 - Math.pow(1 - t, 3);

    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    let vw = window.innerWidth;
    let vh = window.innerHeight;

    /* ---------- Brand flight ---------- */

    const brand = $('.brand');
    const slot = $('.brand-slot');

    function sizeSlot() {
        slot.style.width = `${brand.offsetWidth}px`;
        slot.style.height = `${brand.offsetHeight}px`;
    }

    function placeBrand() {
        const margin = vw < 600 ? 12 : 20;
        const endScale = vw < 600 ? 0.8 : 0.76;
        const r = slot.getBoundingClientRect();
        const p = clamp(window.scrollY / (vh * 0.42));
        const e = reduceMotion ? (p > 0.5 ? 1 : 0) : easeInOut(p);
        const x = lerp(r.left, margin, e);
        const y = lerp(Math.max(r.top, margin), margin, e) + Math.sin(e * Math.PI) * 18;
        const s = lerp(1, endScale, e);
        brand.style.transform = `translate(${x.toFixed(2)}px, ${y.toFixed(2)}px) scale(${s.toFixed(4)})`;
        brand.classList.toggle('is-docked', e > 0.98);
        brand.classList.add('is-placed');
    }

    brand.addEventListener('click', () => window.scrollTo({ top: 0, behavior: reduceMotion ? 'auto' : 'smooth' }));

    /* ---------- Ambient lights ---------- */

    const TONES = {
        light: {
            green: ['#B8E0BD', '#B7DFD3', '#D2E8C6', '#9FD8A6'],
            teal:  ['#B7DFD3', '#A7DCCD', '#D2E8C6', '#63D6C6'],
            sage:  ['#D2E8C6', '#B8E0BD', '#C7E4D8', '#9FD8A6'],
            mint:  ['#A9DDB1', '#B7DFD3', '#D2E8C6', '#63D6C6'],
            lime:  ['#D2E8C6', '#C3E3B5', '#B7DFD3', '#9FD8A6'],
        },
        dark: {
            green: ['#1E6233', '#155A4C', '#2A5422', '#1E6233'],
            teal:  ['#155A4C', '#17605A', '#1E6233', '#155A4C'],
            sage:  ['#2A5422', '#1E6233', '#1E4F3E', '#2A5422'],
            mint:  ['#1E6233', '#256B3A', '#155A4C', '#17605A'],
            lime:  ['#2A5422', '#335E25', '#155A4C', '#1E6233'],
        },
    };

    // Each light: home position (viewport fractions), wander amplitude, speed, phase, size
    const LIGHTS = [
        { bx: 0.86, by: 0.12, ax: 0.22, ay: 0.16, fx: 0.55, fy: 0.8, ph: 0.0, s: 1.0 },
        { bx: 0.12, by: 0.55, ax: 0.18, ay: 0.24, fx: 0.7, fy: 0.5, ph: 1.9, s: 0.95 },
        { bx: 0.62, by: 0.95, ax: 0.3, ay: 0.14, fx: 0.45, fy: 0.65, ph: 3.4, s: 0.85 },
        { bx: 0.35, by: 0.2, ax: 0.26, ay: 0.2, fx: 0.9, fy: 0.6, ph: 4.6, s: 0.5 },
    ];

    const lightEls = $$('.ambient .light');
    const toned = $$('[data-tone]');

    const hexToRgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
    const mixRgb = (a, b, t) => a.map((v, i) => Math.round(lerp(v, b[i], t)));

    function currentTone() {
        // Which section crosses the middle of the screen, and how far toward the next one
        const mid = vh * 0.5;
        let idx = 0;
        for (let i = 0; i < toned.length; i++) {
            if (toned[i].getBoundingClientRect().top <= mid) idx = i;
        }
        const cur = toned[idx];
        const next = toned[Math.min(idx + 1, toned.length - 1)];
        const r = cur.getBoundingClientRect();
        // Blend over the last 40% of the current section
        const t = next === cur ? 0 : clamp((mid - r.top - r.height * 0.6) / (r.height * 0.4));
        return { a: cur.dataset.tone, b: next.dataset.tone, t: easeInOut(t) };
    }

    function updateAmbient() {
        const set = TONES.light;
        const { a, b, t } = currentTone();
        const u = window.scrollY / vh;  // screens scrolled
        const base = Math.max(vw, vh);

        lightEls.forEach((el, i) => {
            const L = LIGHTS[i];
            const m = reduceMotion ? 0 : 1;
            const x = (L.bx + L.ax * Math.sin(u * L.fx + L.ph) * m) * vw;
            const y = (L.by + L.ay * Math.cos(u * L.fy + L.ph) * m) * vh;
            el.style.transform = `translate3d(${x.toFixed(1)}px, ${y.toFixed(1)}px, 0)`;
            el.style.setProperty('--s', `${Math.round(base * 0.95 * L.s)}px`);
            const c = mixRgb(hexToRgb(set[a][i]), hexToRgb(set[b][i]), t);
            el.style.setProperty('--c', `rgb(${c.join(',')})`);
        });

    }

    /* ---------- Cover card: eases back as you leave the cover ---------- */

    const hero = $('.cover');
    const heroCard = $('[data-parallax]');

    function updateHero() {
        if (reduceMotion) return;
        const h = clamp(window.scrollY / (hero.offsetHeight * 0.9));
        if (h >= 1 && heroCard.dataset.done) return;
        heroCard.dataset.done = h >= 1 ? '1' : '';
        heroCard.style.transform = `perspective(1400px) translateY(${(h * 40).toFixed(1)}px) rotateX(${(h * 7).toFixed(2)}deg) scale(${(1 - h * 0.05).toFixed(4)})`;
        heroCard.style.setProperty('--wm-y', `${(-h * 70).toFixed(1)}px`);
        heroCard.style.setProperty('--lx', `${(76 - h * 30).toFixed(1)}%`);
        heroCard.style.setProperty('--ly', `${(12 + h * 30).toFixed(1)}%`);
    }

    /* ---------- Scroll / resize loop ---------- */

    let queued = false;
    function frame() {
        queued = false;
        placeBrand();
        updateAmbient();
        updateHero();
    }
    function queue() {
        if (!queued) {
            queued = true;
            requestAnimationFrame(frame);
        }
    }

    window.addEventListener('scroll', queue, { passive: true });
    window.addEventListener('resize', () => {
        vw = window.innerWidth;
        vh = window.innerHeight;
        sizeSlot();
        queue();
    });

    /* ---------- Reveal on view ---------- */

    $$('[data-stagger]').forEach((group) => {
        [...group.children].forEach((c, i) => c.style.setProperty('--i', i % 6));
    });
    $$('.compare tbody').forEach((tb) => [...tb.rows].forEach((tr, i) => tr.style.setProperty('--i', i)));

    const counted = new WeakSet();
    function countUp(el) {
        if (counted.has(el)) return;
        counted.add(el);
        const target = el.dataset.count;
        const value = parseFloat(target);
        const decimals = (target.split('.')[1] || '').length;
        const pad = target.startsWith('0') && !target.includes('.') ? target.length : 0;
        if (reduceMotion) return;
        const t0 = performance.now();
        const dur = 650;
        const step = (now) => {
            const k = easeOut(clamp((now - t0) / dur));
            let s = (value * k).toFixed(decimals);
            if (pad) s = s.padStart(pad, '0');
            el.textContent = s;
            if (k < 1) requestAnimationFrame(step);
            else el.textContent = target;
        };
        requestAnimationFrame(step);
    }

    const io = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
            if (!entry.isIntersecting) return;
            const el = entry.target;
            el.classList.add('in');
            $$('[data-count]', el).forEach(countUp);
            if (el.dataset.count) countUp(el);
            io.unobserve(el);
        });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.12 });

    $$('[data-reveal], [data-count]').forEach((el) => io.observe(el));

    /* ---------- Posts: gentle tilt + lightbox ---------- */

    const lightbox = $('.lightbox');
    const lightImg = $('img', lightbox);

    $$('.post button').forEach((btn) => {
        btn.addEventListener('click', () => {
            const img = $('img', btn);
            lightImg.src = img.currentSrc || img.src;
            lightImg.alt = img.alt;
            lightbox.showModal();
        });
        if (reduceMotion) return;
        btn.addEventListener('pointermove', (e) => {
            const r = btn.getBoundingClientRect();
            const px = (e.clientX - r.left) / r.width - 0.5;
            const py = (e.clientY - r.top) / r.height - 0.5;
            btn.style.setProperty('--rx', `${(px * 10).toFixed(2)}deg`);
            btn.style.setProperty('--ry', `${(-py * 10).toFixed(2)}deg`);
        });
        btn.addEventListener('pointerleave', () => {
            btn.style.setProperty('--rx', '0deg');
            btn.style.setProperty('--ry', '0deg');
        });
    });

    $('.lightbox-close').addEventListener('click', () => lightbox.close());
    lightbox.addEventListener('click', (e) => { if (e.target === lightbox) lightbox.close(); });

    /* ---------- Start ---------- */

    sizeSlot();
    frame();
    const ready = () => requestAnimationFrame(() => {
        sizeSlot();
        frame();
        hero.classList.add('ready');
    });
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(ready);
    else window.addEventListener('load', ready);
})();

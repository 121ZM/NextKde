// Deterministic CPU particle dynamics. Unitless coordinates and masses.
// Velocity Verlet with a bounded 1/120 s step; no orbit positions are animated.
export function acceleration(position, bodies, softening = 0.018) {
    const a = [0, 0, 0];
    for (const body of bodies) {
        const dx = body.x - position[0], dy = body.y - position[1], dz = body.z - position[2];
        const r2 = dx * dx + dy * dy + dz * dz + softening * softening;
        const force = body.mass / (r2 * Math.sqrt(r2));
        a[0] += dx * force; a[1] += dy * force; a[2] += dz * force;
    }
    return a;
}
export function verlet(p, dt, bodies, drag = 0) {
    const a = acceleration([p.x, p.y, p.z], bodies);
    p.x += p.vx * dt + a[0] * dt * dt * 0.5;
    p.y += p.vy * dt + a[1] * dt * dt * 0.5;
    p.z += p.vz * dt + a[2] * dt * dt * 0.5;
    const b = acceleration([p.x, p.y, p.z], bodies);
    const damping = Math.exp(-drag * dt);
    p.vx = (p.vx + (a[0] + b[0]) * dt * 0.5) * damping;
    p.vy = (p.vy + (a[1] + b[1]) * dt * 0.5) * damping;
    p.vz = (p.vz + (a[2] + b[2]) * dt * 0.5) * damping;
}
function random(i, salt) {
    const n = Math.sin(i * 127.1 + salt * 311.7) * 43758.5453;
    return n - Math.floor(n);
}
export function create(theme, count) {
    const particles = [];
    for (let i = 0; i < count; i++) {
        const angle = random(i, 1) * Math.PI * 2;
        const r = theme === 'blackhole' ? 1.0 + Math.pow(random(i, 2), 0.75) * 5.4
            : 0.55 + Math.pow(random(i, 2), 0.55) * 5.2;
        const speed = Math.sqrt(4.2 / r) * (0.82 + random(i, 3) * 0.26);
        const p = { x: Math.cos(angle) * r, y: (random(i, 4) - 0.5) * 0.15,
            z: Math.sin(angle) * r, vx: -Math.sin(angle) * speed,
            vy: 0, vz: Math.cos(angle) * speed, seed: random(i, 5), trail: [] };
        if (theme === 'weather') {
            p.x = (random(i, 1) - 0.5) * 12;
            p.y = (random(i, 2) - 0.5) * 8;
            p.z = random(i, 3); p.vx = 0.06; p.vy = 0.15; p.vz = 0;
        }
        particles.push(p);
    }
    return { theme, particles, time: 0 };
}
export function advance(state, elapsed, storm = false) {
    const steps = Math.ceil(Math.min(0.20, Math.max(0, elapsed)) * 120);
    if (!steps) return;
    const dt = Math.min(0.20, elapsed) / steps;
    for (let step = 0; step < steps; step++) {
        state.time += dt;
        const bodies = [{ x: 0, y: 0, z: 0, mass: 4.2 }];
        // A moving companion perturbs the galaxy, rather than prescribing paths.
        if (state.theme === 'starfield') bodies.push({ x: Math.cos(state.time * 0.16) * 3,
            y: 0.12, z: Math.sin(state.time * 0.16) * 3, mass: 0.16 });
        for (const p of state.particles) {
            if (state.theme === 'weather') {
                const wind = 0.24 * Math.sin(state.time * 0.24 + p.z * 6);
                // Gravity plus linear aerodynamic drag, terminal speed bounded.
                p.vx += (wind - p.vx) * dt * 0.6;
                p.vy += ((storm ? 3.8 : 0.28) - p.vy * (storm ? 0.8 : 1.4)) * dt;
                p.x += p.vx * dt; p.y += p.vy * dt;
                if (p.y > 4.4) { p.y = -4.4; p.trail = []; }
                if (p.x > 6.4) p.x = -6.4;
                if (p.x < -6.4) p.x = 6.4;
            } else {
                verlet(p, dt, bodies, state.theme === 'blackhole' ? 0.004 : 0);
                const r = Math.hypot(p.x, p.z);
                if (r < 0.68 || r > 12) {
                    const angle = p.seed * Math.PI * 2 + state.time * 0.1;
                    const radius = 4.5 + p.seed * 1.8, speed = Math.sqrt(4.2 / radius);
                    p.x = Math.cos(angle) * radius; p.z = Math.sin(angle) * radius;
                    p.vx = -Math.sin(angle) * speed; p.vz = Math.cos(angle) * speed;
                    p.trail = [];
                }
            }
        }
    }
    for (const p of state.particles) {
        p.trail.unshift([p.x, p.y, p.z]);
        if (p.trail.length > 9) p.trail.pop();
    }
}

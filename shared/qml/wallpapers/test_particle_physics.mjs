import assert from 'node:assert/strict';
import { acceleration, verlet, create, advance } from './ParticlePhysics.mjs';
const bodies = [{x:0,y:0,z:0,mass:4.2}];
assert.deepEqual(acceleration([0,0,0], bodies), [0,0,0]);
const p={x:2,y:0,z:0,vx:0,vy:0,vz:Math.sqrt(4.2/2)};
const energy = p => (p.vx**2+p.vy**2+p.vz**2)/2-4.2/Math.sqrt(p.x**2+p.y**2+p.z**2+0.018**2);
const initialEnergy=energy(p), initialMomentum=p.x*p.vz-p.z*p.vx;
for(let i=0;i<24000;i++) verlet(p,1/120,bodies);
assert.ok(Math.abs(energy(p)-initialEnergy)<0.00001,'orbital energy must remain bounded over 200 seconds');
assert.ok(Math.abs(p.x*p.vz-p.z*p.vx-initialMomentum)<0.000001,'central force conserves angular momentum');
for(const theme of ['starfield','blackhole','weather']) {
    const a=create(theme,200), b=create(theme,200);
    advance(a,0.1,true); advance(b,0.1,true);
    assert.deepEqual(a,b,'independent foreground/background simulations must agree');
    const snapshot=JSON.stringify(a);
    advance(a,0,true); assert.equal(JSON.stringify(a),snapshot,'pausing must not integrate motion');
    for(let i=0;i<400;i++) advance(a,0.2,true);
    for(const particle of a.particles) {
        assert.ok(Number.isFinite(particle.x+particle.y+particle.z+particle.vx+particle.vy+particle.vz));
        assert.ok(particle.trail.length<=9);
        if(theme==='weather') assert.ok(particle.y<=4.4 && particle.y>=-4.4);
    }
    const bounded=create(theme,10), delayed=create(theme,10);
    advance(bounded,0.2); advance(delayed,600);
    assert.deepEqual(bounded,delayed,'no catch-up after an idle interval');
}
console.log('Particle physics: energy, angular momentum, deterministic layers, drag, finite trajectories and bounded steps passed.');

// Benchmarks criterion — stub (le puzzle agent ajoutera les vrais benches)
use criterion::{criterion_group, criterion_main, Criterion};

fn bench_ping(c: &mut Criterion) {
    c.bench_function("engine_ping", |b| {
        b.iter(|| {
            // Stub : appel trivial pour valider que criterion compile
            let x: i32 = 42;
            criterion::black_box(x)
        })
    });
}

criterion_group!(benches, bench_ping);
criterion_main!(benches);

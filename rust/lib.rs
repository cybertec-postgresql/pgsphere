// https://users.rust-lang.org/t/pass-a-vec-from-rust-to-c/59184/6

use cdshealpix::nested::cone_coverage_approx;
use ::safer_ffi::prelude::*;

#[ffi_export]
fn cone_coverage (depth: u8, cone_lon: f64, cone_lat: f64, cone_radius: f64) -> repr_c::Vec<u64>
{
    let moc = cone_coverage_approx(depth, cone_lon, cone_lat, cone_radius).to_ranges();

    let moc_iter = moc.into_iter();
    let mut pixels: Vec<u64> = vec![];
    for range in moc_iter {
        pixels.push(range.start);
        pixels.push(range.end);
    }

    pixels.into()
}

#[ffi_export]
fn free_vec (vec: repr_c::Vec<u64>)
{
    drop(vec);
}

#[cfg(feature = "generate-headers")]
#[test]
fn generate_headers ()
  -> ::std::io::Result<()>
{
    ::safer_ffi::headers::builder()
        .to_file("rust/cone.h")?
        .generate()
}

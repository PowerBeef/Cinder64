#![deny(warnings)]
#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

pub mod cheats;
pub mod device;
pub mod netplay;
pub mod retroachievements;
pub mod savestates;
pub mod ui;


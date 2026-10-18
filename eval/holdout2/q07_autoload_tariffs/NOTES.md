# q07_autoload_tariffs

`ZoneTable` and `Tariff` are registered with `Module#autoload` and not required by `spec_helper`; their
files (including the `BY_COUNTRY` index inverted from `ZONES` and the `REST_OF_WORLD` arithmetic) run inside
whichever example first names the constant. Which example pays for the load depends on order, and the
load-time lines run exactly once per process.

using Pkg.Artifacts
using Pkg.BinaryPlatforms
using JSON

package_dict = JSON.parsefile(joinpath(@__DIR__, "package.json"))
pkgname = package_dict["name"]
version = VersionNumber(package_dict["version"])
vega_version = VersionNumber(package_dict["dependencies"]["vega"])
vegalite_version = VersionNumber(package_dict["dependencies"]["vega-lite"])
vegaembed_version = VersionNumber(package_dict["dependencies"]["vega-embed"])

build_path = joinpath(@__DIR__, "build")

if ispath(build_path)
    rm(build_path, force=true, recursive=true)
end

mkpath(build_path)

artifact_toml = joinpath(build_path, "Artifacts.toml")

platforms = [
    # glibc Linuces
    Linux(:i686),
    Linux(:x86_64),
    Linux(:aarch64),
    Linux(:armv7l),
    Linux(:powerpc64le),

    # musl Linuces
    Linux(:i686, libc=:musl),
    Linux(:x86_64, libc=:musl),
    Linux(:aarch64, libc=:musl),
    Linux(:armv7l, libc=:musl),

    # BSDs
    MacOS(:x86_64),
    FreeBSD(:x86_64),

    # Windows
    Windows(:i686),
    Windows(:x86_64),
]

npm_cmd = Sys.iswindows() ? "npm.cmd" : "npm"
nodepregyp_cmd = Sys.iswindows() ? "node-pre-gyp.cmd" : "node-pre-gyp"

for platform in platforms

    l_libc = platform isa Linux ? "glibc" : "unknown"

    product_hash = create_artifact() do artifact_dir
        cp(joinpath(@__DIR__, "package.json"), joinpath(artifact_dir, "package.json"))
        cp(joinpath(@__DIR__, "package-lock.json"), joinpath(artifact_dir, "package-lock.json"))

        if arch(platform)==:x86_64 && (platform isa Windows || platform isa MacOS || (platform isa Linux && libc(platform)==:glibc))
            l_arch = arch(platform)==:x86_64 ? "x64" : arch(platform)==:i686 ? "ia32" : arch(platform)==:armv7l ? "arm" : error("Unknown arch.")
            l_target = platform isa MacOS ? "darwin" : platform isa Windows ? "win32" : platform isa Linux ? "linux" : platform isa FreeBSD ? "freebsd" : error("Unknown target.")
            run(Cmd(`$npm_cmd install --ignore-scripts --production --no-package-lock --no-optional`, dir=artifact_dir))
            canvas_path = abspath(joinpath(artifact_dir, "node_modules", "canvas"))
            run(Cmd(`$nodepregyp_cmd install -C $canvas_path --target_arch=$l_arch --target_platform=$l_target --target_libc=$l_libc`, dir=joinpath(artifact_dir, "node_modules", ".bin")))
        else
            run(Cmd(`$npm_cmd uninstall vega-cli --save`, dir=artifact_dir))
            run(Cmd(`$npm_cmd uninstall canvas --save`, dir=artifact_dir))
            run(Cmd(`$npm_cmd install --ignore-scripts --production --no-package-lock --no-optional`, dir=artifact_dir))
        end
        run(Cmd(`$npm_cmd prune --production`, dir=artifact_dir))

        mkpath(joinpath(artifact_dir, "minified"))
        mkpath(joinpath(artifact_dir, "schemas"))

        download("https://vega.github.io/schema/vega/v$vega_version.json", joinpath(artifact_dir, "schemas", "vega-schema.json"))
        download("https://vega.github.io/schema/vega-lite/v$vegalite_version.json", joinpath(artifact_dir, "schemas", "vega-lite-schema.json"))
        download("https://cdn.jsdelivr.net/npm/vega@$vega_version", joinpath(artifact_dir, "minified", "vega.min.js"))
        download("https://cdn.jsdelivr.net/npm/vega-lite@$vegalite_version", joinpath(artifact_dir, "minified", "vega-lite.min.js"))
        download("https://cdn.jsdelivr.net/npm/vega-embed@$vegaembed_version", joinpath(artifact_dir, "minified", "vega-embed.min.js"))
    end

    download_hash = archive_artifact(product_hash, joinpath(build_path, "$pkgname-$version-$(triplet(platform)).tar.gz"))

    bind_artifact!(artifact_toml, "vegalite_app", product_hash, platform=platform, force=true, download_info=Tuple[("httpssomething", download_hash)])
end

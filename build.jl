using Pkg.Artifacts
using Pkg.BinaryPlatforms
using JSON
import URIParser
import NodeJS_16_jll

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
    MacOS(:aarch64),
    FreeBSD(:x86_64),

    # Windows
    Windows(:i686),
    Windows(:x86_64),
]

nodejs_cmd = NodeJS_16_jll.node()
npm_cmd = Sys.iswindows() ? `$(string(NodeJS_16_jll.npm, ".cmd"))` : `$nodejs_cmd $(NodeJS_16_jll.npm)`

for platform in platforms

    l_libc = platform isa Linux ? "glibc" : "unknown"

    product_hash = create_artifact() do artifact_dir
        cp(joinpath(@__DIR__, "package.json"), joinpath(artifact_dir, "package.json"))
        cp(joinpath(@__DIR__, "package-lock.json"), joinpath(artifact_dir, "package-lock.json"))
        cp(joinpath(@__DIR__, "vg2svg.js"), joinpath(artifact_dir, "vg2svg.js"))
        cp(joinpath(@__DIR__, "vl2vg.js"), joinpath(artifact_dir, "vl2vg.js"))

        bin_links_flat = platform isa Windows ? "--no-bin-links" : ""

        if platform isa MacOS || (arch(platform)==:x86_64 && (platform isa Windows || (platform isa Linux && libc(platform)==:glibc)))
            l_arch = platform isa MacOS ? "x64" : arch(platform)==:x86_64 ? "x64" : arch(platform)==:i686 ? "ia32" : arch(platform)==:armv7l ? "arm" : error("Unknown arch.")
            l_target = platform isa MacOS ? "darwin" : platform isa Windows ? "win32" : platform isa Linux ? "linux" : platform isa FreeBSD ? "freebsd" : error("Unknown target.")
            run(Cmd(`$npm_cmd install --scripts-prepend-node-path=true --ignore-scripts --production --no-package-lock --no-optional $bin_links_flat`, dir=artifact_dir))
            canvas_path = abspath(joinpath(artifact_dir, "node_modules", "canvas"))
            run(Cmd(`$npm_cmd install @mapbox/node-pre-gyp --save`))
            if Sys.iswindows()
                run(Cmd(`node-pre-gyp.cmd install -C $canvas_path --target_arch=$l_arch --target_platform=$l_target --target_libc=$l_libc`, dir=joinpath(artifact_dir, "node_modules", ".bin")))
            else
                run(Cmd(`$nodejs_cmd node-pre-gyp install -C $canvas_path --target_arch=$l_arch --target_platform=$l_target --target_libc=$l_libc`, dir=joinpath(artifact_dir, "node_modules", ".bin")))
            end
        else
            run(Cmd(`$npm_cmd uninstall vega-cli --scripts-prepend-node-path=true --save`, dir=artifact_dir))
            run(Cmd(`$npm_cmd uninstall canvas --scripts-prepend-node-path=true --save`, dir=artifact_dir))
            run(Cmd(`$npm_cmd install --scripts-prepend-node-path=true --ignore-scripts --production --no-package-lock --no-optional $bin_links_flat`, dir=artifact_dir))
        end
        run(Cmd(`$npm_cmd prune --production --scripts-prepend-node-path=true`, dir=artifact_dir))

        mkpath(joinpath(artifact_dir, "minified"))
        mkpath(joinpath(artifact_dir, "schemas"))

        download("https://vega.github.io/schema/vega/v$vega_version.json", joinpath(artifact_dir, "schemas", "vega-schema.json"))
        download("https://vega.github.io/schema/vega-lite/v$vegalite_version.json", joinpath(artifact_dir, "schemas", "vega-lite-schema.json"))
        download("https://cdn.jsdelivr.net/npm/vega@$vega_version", joinpath(artifact_dir, "minified", "vega.min.js"))
        download("https://cdn.jsdelivr.net/npm/vega-lite@$vegalite_version", joinpath(artifact_dir, "minified", "vega-lite.min.js"))
        download("https://cdn.jsdelivr.net/npm/vega-embed@$vegaembed_version", joinpath(artifact_dir, "minified", "vega-embed.min.js"))

        if platform isa Windows
            for (root, dirs, files) in walkdir(artifact_dir) 
                cd(root) do
                    for file in files
                        run(`chmod +x "$file"`)
                    end
                end
            end
        end
    end

    archive_filename = "$pkgname-$version-$(triplet(platform)).tar.gz"

    download_hash = archive_artifact(product_hash, joinpath(build_path, archive_filename))

    bind_artifact!(artifact_toml, "vegalite_app", product_hash, platform=platform, force=true, download_info=Tuple[("https://github.com/queryverse/VegaLiteBuilder/releases/download/v$(URIParser.escape(string(version)))/$archive_filename", download_hash)])
end

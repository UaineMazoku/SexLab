set_project("SexLab")
set_version("2.17.0")

includes("xmake/dotenv")
includes("xmake/papyrus")
includes("xmake/spriggit")

option("xse_tes5_mods_path")
    set_category("xse")
    set_description("Path to mods directory")
    on_check("dotenv.check")

option("xse_tes5_game_path")
    set_category("xse")
    set_description("Path to game directory")
    on_check("dotenv.check")

option("xse_mod_name")
    set_category("xse")
    set_description("Name of the mod folder for install")
    set_default("SL-Dev")
    after_check("dotenv.check")

option("papyrus_include")
    add_deps("xse_tes5_mods_path")
    set_category("papyrus")
    set_description("Path to papyrus include directories",
                    'Defaults to: "%$(xse_tes5_mods_path)"')
    on_check(function(option)
        import("dotenv.check")(option, vformat("$(xse_tes5_mods_path)"))
    end)

option("papyrus_gamedata")
    set_category("papyrus")
    add_deps("xse_tes5_game_path")
    set_description("Path to game script sources",
                    'Defaults to: "%$(xse_tes5_game_path)/Data"')
    on_check(function(option)
        import("dotenv.check")(option, vformat("$(xse_tes5_game_path)/Data"))
    end)

option("do_install")
    set_description("Automatically trigger an install after successful build")
    set_default(false)
    after_check("dotenv.check")

-- ensure dotenv is loaded before imported options
option("papyrus_path")
    add_deps("dotenv")
option("spriggit_path")
    add_deps("dotenv")

rule("common")
    on_config(function(target)
        import("core.project.config")
        local mods_path = config.get("xse_tes5_mods_path")
        local mod_name = config.get("xse_mod_name")

        print("common:on_config", target:name())

        if mods_path and mod_name then
            target:set("installdir", path.join(mods_path, mod_name))
        end
    end)

    after_build(function(target)
        import("core.project.config")
        local do_install = config.get("do_install")
        if do_install then
            task.run("install", {target = target:name()})
        end
    end)
rule_end()

add_rules("common")

target("papyrus")
    set_kind("object")
    set_targetdir("Scripts")
    set_basename("SexLab")

    --avoid rebuild on mode change
    set_policy("build.intermediate_directory", false)

    add_rules("papyrus")

    on_load(function(target)
        import("core.project.config")

        if not config.get("papyrus_include") then
            cprint("${color.warning}papyrus_include is not defined")
        end
        if not config.get("papyrus_gamedata") then
            cprint("${color.warning}papyrus_gamedata is not defined")
        end
    end)

    add_files("Source/Scripts/*.psc")

    add_includedirs("$(curdir)/Source/Scripts")
    add_includedirs("$(papyrus_include)/SkyrimLovense/Source/Scripts")
    add_includedirs("$(papyrus_include)/PapyrusUtil SE - Modders Scripting Utility Functions/Source/Scripts")
    add_includedirs("$(papyrus_include)/SkyUI SDK/Source/Scripts")
    add_includedirs("$(papyrus_include)/XP32 Maximum Skeleton Special Extended/Source/Scripts")
    add_includedirs("$(papyrus_include)/Race Menu Sources/Source/Scripts")
    add_includedirs("$(papyrus_include)/ConsoleUtil Extended/Source/Scripts")
    add_includedirs("$(papyrus_include)/JContainers SE/source/scripts")
    add_includedirs("$(papyrus_include)/UIExtensions/Source/Scripts")
    add_includedirs("$(papyrus_include)/MfgFix NG/Source/Scripts")
    add_includedirs("$(papyrus_include)/Mfg Fix/Source/Scripts")
    add_includedirs("$(papyrus_include)/AnimSpeedSE/Source/Scripts")
    add_includedirs("$(papyrus_gamedata)/Source/Scripts")
target_end()

target("SexLab.esm")
    set_kind("object")
    set_targetdir(".")

    --avoid rebuild on mode change
    set_policy("build.intermediate_directory", false)

    add_rules("spriggit")
    set_values("spriggit.srcdir", "res/SexLab.esm")
target_end()

target("assets")
    set_kind("phony")
    set_default(false)
    add_installfiles("(Interface/SexLab/**)")
    add_installfiles("(Interface/Translations/*.txt)")
    add_installfiles("(SKSE/CustomConsole/*.yaml)")
    add_installfiles("(SKSE/SexLab/**)")

    add_installfiles("(meshes/**)")
    add_installfiles("(textures/**)")
    add_installfiles("(Sound/**)")
target_end()

task("serialize")
    on_run(function()
        import("core.project.config")
        import("core.base.option")
        import("core.base.task")
        import("dotenv")
        config.load()
        dotenv.load()

        task.run("config")
        task.run("spriggit.serialize", {
            target = "SexLab.esm",
            install = option.get("install"),
        })
    end)

    set_menu {
        shortname = 's',
        usage = "xmake serialize [-i | <srcfile>]",
        description = "Serialize project",
        options = {
            {'i', "install",    "k",  nil, "Serialize from installdir." },
            {'o', "installdir", "kv", nil, "Override the install directory."},
        }
    }
task_end()

includes("@builtin/xpack")

xpack("SexLab")
    set_formats("zip")
    set_extension(".7z")
    set_basename("SexLab Framework PPLUS - V$(version)")
    add_targets("papyrus", "assets", "SexLab.esm")

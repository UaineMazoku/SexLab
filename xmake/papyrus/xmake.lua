add_moduledirs("modules")

option("papyrus_path")
    set_description("Path to Papyrus Compiler directory")
    set_category("papyrus")

task("papyrus.anonymize")
    on_run("papyrus.anonymize")
    -- function()
    --     import("core.base.option")
    --     local file = option.get("pex_file")
    --     import("papyrus.anonymize")(file)
    -- end)

    set_menu {
                -- Settings menu usage
                usage = "xmake papyrus.anonymize <file>",

                -- Setup menu description
                description = "Anonymize the pex header.",

                -- Set menu options, if there are no options, you can set it to {}
                options =
                {
                    {nil, "file", "v", nil, "The file to anonymize." },
                }
            }
task_end()

task("papyrus.project")
    on_run("project")
    set_menu {
        usage = "xmake papyrus.project <target>",
        description = "Generate a papyrus project file.",
        options = {
            {'o', "outdir", "kv", ".", "Set the output directory." },
            {nil, "target", "v", nil, "The target to generate."},
        }
    }

task("papyrus.check")
    on_run(function()
        import("lib.detect.find_tool")
        print(find_tool("papyrus"))
    end)
    set_menu { options = {} }

rule("papyrus")
    set_extensions(".psc")

    on_config(function(target)
        -- local batch = target:sourcebatches().papyrus
        -- print(target:fileconfig(batch.sourcefiles[1]))
        import("papyrus").do_config(target)
    end)

    before_build(function (target)
        import("lib.detect.find_tool")
        local compiler = assert(find_tool("papyrus"), "PapyrusCompiler not found!")
        target:data_add("papyrus", {compiler = compiler.program})
    end)

    on_build_file(function (...)
        import("papyrus").build_file(...)
    end)

    -- Using on_build_file because vrunv doesn't properly report papyrus compile errors
    -- on_buildcmd_file(function (...)
    --     import("papyrus").buildcmd_file(...)
    -- end)
rule_end()

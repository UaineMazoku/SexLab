import("core.base.xml")
import("core.base.bytes")
import("core.project.config")
import("core.base.option")
import("lib.detect.find_tool")

---comment
---@param node table
---@param xpath string
---@return fun():table
function _node_iter(node, xpath)
    local i = 0
    ---@return table
    return function()
        i = i + 1
        return xml.find(node, xpath .. "[" .. i .. "]")
    end
end

function _load_project(project)
    local base = path.directory(project)
    local ppj = xml.loadfile(project)

    local ret = {}

    ---@type { [string]: string }
    ret.vars = {}
    for node in _node_iter(ppj, "/PapyrusProject/Variables/Variable") do
        ret.vars[node.attrs.Name] = node.attrs.Value
    end

    ret.imports = {}
    for node in _node_iter(ppj, "/PapyrusProject/Imports/Import/text()") do
        table.insert(ret.imports, node.text)
    end

    ret.folders = {}
    for node in _node_iter(ppj, "/PapyrusProject/Folders/Folder/text()") do
        table.insert(ret.folders, node.text)
    end

    ret.scripts = {}
    for node in _node_iter(ppj, "/PapyrusProject/Scripts/Script/text()") do
        table.insert(ret.scripts, node.text)
    end

    local function bool_attr(attr)
        local value = ppj.attrs[attr] or ""
        return value:lower() == "true"
    end

    ret.flags = ppj.attrs.Flags
    ret.output = ppj.attrs.Output
    ret.optimize = bool_attr("Optimize")
    ret.anonymize = bool_attr("Anonymize")

    return ret
end

function _expand_vars(str, vars)
    for k, v in pairs(vars) do
        str = str:gsub('@' .. k, v)
    end
    return str
end

_REG_VALUE = "HKLM\\SOFTWARE\\WOW6432Node\\Bethesda Softworks\\Skyrim Special Edition;Installed Path"

function _check_path(p)
    if p and path.is_absolute(p) then
        p = path.normalize(p)
        if path.filename(p) ~= "PapyrusCompiler.exe" then
            if path.filename(p) ~= "Papyrus Compiler" then
                p = path.join(p, "Papyrus Compiler")
            end
            p = path.join(p, "PapyrusCompiler.exe")
        end
        if os.isfile(p) then
            return true, p
        end
    end
    return false
end

function _swap_source_scripts(dir)
    local s = path.split(dir)
    local n = #s
    if #s > 2 then
        local t0 = s[n]:lower()
        local t1 = s[n-1]:lower()
        if (t0 == "source" and t1 == "scripts") or (t0 == "scripts" and t1 == "source") then
            s[n-1] = t0
            s[n] = t1
            return path.join(unpack(s))
        end
    end
end

---Get papyrus objectfile name
---@param target Target
---@param sourcefile string
---@param absolute boolean?
---@return string
function _objectfile(target, sourcefile, absolute)
    local objectfile = path.join(target:targetdir(), path.basename(sourcefile) .. ".pex")
    if absolute then
        objectfile = path.absolute(objectfile, os.projectdir())
    end
    return path.normalize(objectfile)
end

---@param target Target
function do_config(target)
    local conf = target:extraconf("rules", "papyrus")

    -- if not find_tool("papyrus") then
    --     cprint("${color.warning}PapyrusCompiler not found.\n${clear dim}Set PAPYRUS_PATH in env or config.")
    -- end

    local papyrus = {
        game = "sse",
        flags = "TESV_Papyrus_Flags.flg",
        optimize = true,
        anonymize = true,
    }
    table.join2(papyrus, conf)

    target:data_set("papyrus", papyrus)

    local batch = target:sourcebatches().papyrus
    local sourcefiles = batch and batch.sourcefiles or {}
    for _, v in ipairs(sourcefiles) do
        local objectfile = _objectfile(target, v)
        target:add("installfiles", sourcefiles, {prefixdir = "Source/Scripts"})
        target:add("installfiles", objectfile, {prefixdir = "Scripts"})
    end

    local includedirs = {}
    for _, dir in ipairs(target:get("includedirs")) do
        local norm_dir = path.normalize(path.absolute(vformat(dir), '$(projectdir)'))
        if os.isdir(norm_dir) then
            table.insert(includedirs, norm_dir)
        else
            local swap_dir = _swap_source_scripts(norm_dir)
            if swap_dir and os.isdir(swap_dir) then
                cprint('${dim}Papyrus: Swapping include "%s" to "%s"', norm_dir, swap_dir)
                table.insert(includedirs, swap_dir)
            else
                cprint('${color.warning}Papyrus: Include dir "%s" does not exist', norm_dir)
                table.insert(includedirs, norm_dir)
            end
        end
    end
    target:set("includedirs", includedirs)
end

--- Custom vexecv to properly capture PapyrusCompiler error output
function _vexecv(program, argv)
    -- make temporary output and error file
    local outfile = os.tmpfile()
    local errfile = os.tmpfile()
    local opt = {}
    opt.try = true
    opt.stdout = outfile
    opt.stderr = errfile

    -- run command
    local ok, errors = os.vexecv(program, argv, opt)
    -- local outdata = io.readfile(outfile)
    local errdata = io.readfile(errfile)
    os.rm(outfile)
    os.rm(errfile)

    if ok ~= 0 then
        -- get command
        local cmd = program
        if argv then
            cmd = cmd .. " " .. os.args(argv)
        end
        -- get errors
        if ok ~= nil then
            errors = string.format("execv(%s) failed(%d)", cmd, ok)
            if errdata then
                errors = errors .. "\n" .. errdata
            end
        else
            errors = string.format("cannot execv(%s), %s", cmd, errors and errors or "unknown reason")
        end
        os.raise(errors)
    end
end

---comment
---@param target Target
---@param sourcefile string
---@param opt table
function build_file(target, sourcefile, opt)
    import("core.base.task")
    import("core.project.depend")
    import("utils.progress")

    if path.extension(sourcefile) ~= ".psc" then
        return
    end

    local papyrus = target:data("papyrus") or {}

    local objectfile = _objectfile(target, sourcefile, true)
    local outdir = path.directory(objectfile)

    table.insert(target:objectfiles(), objectfile)

    depend.on_changed(function()
        local args = {
            sourcefile,
            "-f=" .. papyrus.flags,
            "-o=" .. outdir,
            "-i=" .. table.concat(target:get("includedirs"), ";"),
            "-q",
        }

        if papyrus.optimize then
            table.insert(args, "-optimize")
        end

        progress.show(opt.progress, "${color.build.object}Compiling %s...", sourcefile)
        _vexecv(papyrus.compiler, args)

        if papyrus.anonymize then
            progress.show(opt.progress, "${color.build.object}Anonymizing %s...", objectfile)
            import("papyrus.anonymize")(objectfile)
        end
    end, {
        dependfile = target:dependfile(objectfile),
        files = sourcefile,
        values = {
            papyrus.optimize and "optimize" or nil,
            papyrus.anonymize and "anonymize" or nil
        },
        changed = target:is_rebuilt(),
    })
end

function buildcmd_file(target, batchcmds, sourcefile, opt)
    import('lib.detect.find_tool')

    local papyrus = target:data("papyrus") or {}
    assert(papyrus.flags, "papyrus flags not defined!")

    local compiler = assert(papgityrus.compiler, "PapyrusCompiler not found!")

    local objectfile = _objectfile(target, sourcefile, true)
    local outdir = path.directory(objectfile)
    table.insert(target:objectfiles(), objectfile)

    local args = {
        sourcefile,
        "-f=" .. papyrus.flags,
        "-o=" .. outdir,
        "-i=" .. table.concat(target:get("includedirs"), ";"),
        "-q",
    }
    if papyrus.optimize then
        table.insert(args, "-op")
    end

    batchcmds:show_progress(opt.progress, "${color.build.object}Compiling %s...", sourcefile)
    batchcmds:vrunv(compiler, args)

    if papyrus.anonymize then
        batchcmds:show_progress(opt.progress, "${color.build.object}Anonymizing %s...", objectfile)
        batchcmds:vlua("papyrus.anonymize", {objectfile})
    end

    batchcmds:add_depfiles(sourcefile)
    batchcmds:set_depmtime(os.mtime(objectfile))
    batchcmds:set_depcache(target:dependfile(objectfile))
    batchcmds:add_depvalues({
        papyrus.optimize and "optimize" or nil,
        papyrus.anonymize and "anonymize" or nil
    })
end

import("core.cache.memcache")
import("core.project.config")
import("dotenv")

function main(option, default)
    local value = option:value()
    local name = option:name()
    default = default or option:get("default")
    if not value or value == default then
        dotenv.load()
        value = os.getenv(name)
        if value then
            if type(option:get("default")) == "boolean" then
                option:set_value(value == "y")
            else
                option:set_value(value)
            end
            return
        end
    end
    if value == nil and default ~= nil then
        option:set_value(default)
    end
end

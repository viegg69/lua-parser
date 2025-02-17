local cli = {
    count = 0,
    name = '',
    toast = function(self, index, size, text, sleep)
        if type(index) == "string" and type(size) == "string" and not text then
            gg.toast(string.format("%s\n\n\t%s:\n\t%s\n\n", self.name, size, index))
            gg.sleep(sleep or 20)
        else
            if self:pt(index, size) then
                local count = self.count * (size > 100 and 1 or 10)
                gg.toast(text and string.format("%s\n\n\t%s %d%%\n\n", self.name, text, count) or count .. "%")
                gg.sleep(sleep or 20)
            else
                return false
            end
        end
    end,
    pt = function(self, index, size)
        local pt = size > 100 and 100 or 10
        local size = size / pt
        local count = index / size
        if self.count < count and count <= pt then
            self.count = count
            return count
        end
    end,
}

return gg and cli or {error='not support cli'}
--[[
  Module: Scope
  Mục đích:
    Quản lý phạm vi (scope) của các biến trong quá trình biên dịch, bao gồm:
      - Tạo scope mới (local và global)
      - Quản lý danh sách biến, ánh xạ tên biến sang id, và theo dõi số lượng tham chiếu
      - Hỗ trợ xử lý mối quan hệ giữa các scope (cha – con)
      - Hỗ trợ đổi tên biến (rename) nhằm tránh xung đột
  Tác giả: VieGG
  Ngày tạo: 18/2/2025
]]


local config = {IdentPrefix = "__viegg_"}

local Scope = {};

-- Biến đếm dùng để tạo tên mặc định cho các local scope.
local scopeI = 0;
-- Hàm tăng biến đếm và tạo tên mới cho scope.
local function nextName()
	scopeI = scopeI + 1;
	return "local_scope_" .. tostring(scopeI);
end

-- Hàm tạo ra thông báo cảnh báo (warning) dựa trên token và thông điệp.
local function generateWarning(token, message)
	return "Warning at Position " .. tostring(token.line) .. ":" .. tostring(token.linePos) .. ", " .. message;
end

--------------------------------------------------------------------------------
-- Tạo một Local Scope mới.
-- @param parentScope: Scope cha mà scope mới sẽ kế thừa.
-- @param name: (Tùy chọn) Tên của scope, nếu không có thì sẽ tạo tên mặc định.
-- @return: Một đối tượng scope mới.
--------------------------------------------------------------------------------
function Scope:new(parentScope, name)
	local scope = {
		isGlobal = false,                   -- Đây là scope cục bộ.
		parentScope = parentScope,          -- Scope cha.
		variables = {},                     -- Danh sách tên các biến được khai báo trong scope.
		referenceCounts = {};               -- Theo dõi số lượng tham chiếu của từng biến.
		variablesLookup = {},               -- Bảng ánh xạ từ tên biến sang id (vị trí trong mảng variables).
		variablesFromHigherScopes = {},     -- Lưu các biến được tham chiếu từ các scope cao hơn.
		skipIdLookup = {};                  -- Đánh dấu các id bị bỏ qua (ví dụ: biến bị xóa).
		name = name or nextName(),          -- Tên của scope, nếu không có thì tạo tên mặc định.
		children = {},                      -- Danh sách các scope con.
		level = parentScope.level and (parentScope.level + 1) or 1;  -- Mức độ lồng nhau của scope.
	}
	
	setmetatable(scope, self);
	self.__index = self;
	-- Thêm scope mới vào danh sách children của scope cha.
	parentScope:addChild(scope);
	return scope;
end

--------------------------------------------------------------------------------
-- Tạo một Global Scope mới.
-- @return: Một đối tượng global scope.
--------------------------------------------------------------------------------
function Scope:newGlobal()
	local scope = {
		isGlobal = true,                    -- Đây là global scope.
		parentScope = nil,                  -- Không có scope cha.
		variables = {},                     -- Danh sách biến cho global scope.
		variablesLookup = {};               -- Bảng ánh xạ tên biến sang id.
		referenceCounts = {};               -- Số lượng tham chiếu của các biến.
		skipIdLookup = {};                  -- Danh sách các id bị bỏ qua.
		name = "global_scope",              -- Tên của global scope.
		children = {},                      -- Danh sách scope con.
		level = 0,                          -- Level của global scope là 0.
	};
	
	setmetatable(scope, self);
	self.__index = self;
	
	return scope;
end

--------------------------------------------------------------------------------
-- Lấy scope cha của scope hiện hành.
-- @return: Scope cha.
--------------------------------------------------------------------------------
function Scope:getParent()
	return self.parentScope;
end

--------------------------------------------------------------------------------
-- Đổi scope cha của scope hiện hành.
-- Loại bỏ scope này khỏi danh sách children của scope cũ và thêm vào scope mới.
-- @param parentScope: Scope mới làm cha.
--------------------------------------------------------------------------------
function Scope:setParent(parentScope)
	self.parentScope:removeChild(self);
	parentScope:addChild(self);
	self.parentScope = parentScope;
	self.level = parentScope.level + 1;
end

local next_name_i = 1;  -- Biến đếm dùng để tạo tên biến mặc định.

--------------------------------------------------------------------------------
-- Thêm một biến vào scope và trả về id của biến đó.
-- Nếu không truyền tên, một tên mặc định được tạo dựa trên config.IdentPrefix.
-- @param name: Tên của biến.
-- @param token: (Tùy chọn) Token chứa vị trí, dùng cho cảnh báo.
-- @return: id của biến mới.
--------------------------------------------------------------------------------
function Scope:addVariable(name, token)
	if (not name) then
		name = string.format("%s%i", config.IdentPrefix, next_name_i);
		next_name_i = next_name_i + 1;
	end
	
	-- Nếu biến đã tồn tại trong scope, gửi cảnh báo.
	if self.variablesLookup[name] ~= nil then
		if(token) then
			print("warn:", generateWarning(token, "the variable \"" .. name .. "\" is already defined in that scope"));
		else
			gg.alert(string.format("Một biến có tên \"%s\" đã được định nghĩa, bạn không nên có biến nào bắt đầu bằng \"%s\"", name, config.IdentPrefix));
		end
		
		-- Có thể trả về id hiện tại nếu muốn: return self.variablesLookup[name];
	end
	
	-- Thêm tên biến vào danh sách và cập nhật ánh xạ.
	table.insert(self.variables, name);
	local id = #self.variables;
	self.variablesLookup[name] = id;
	return id;
end

--------------------------------------------------------------------------------
-- Kích hoạt lại một biến bằng cách đảm bảo tên biến được ánh xạ chính xác.
-- @param id: id của biến cần kích hoạt.
--------------------------------------------------------------------------------
function Scope:enableVariable(id)
	local name = self.variables[id];
	self.variablesLookup[name] = id;
end

--------------------------------------------------------------------------------
-- Thêm một biến bị vô hiệu (disabled) vào scope, không cập nhật bảng tra cứu.
-- @param name: Tên biến.
-- @param token: (Tùy chọn) Token dùng để cảnh báo.
-- @return: id của biến mới được thêm.
--------------------------------------------------------------------------------
function Scope:addDisabledVariable(name, token)
	if (not name) then
		name = string.format("%s%i", config.IdentPrefix, next_name_i);
		next_name_i = next_name_i + 1;
	end
	
	if self.variablesLookup[name] ~= nil then
		if(token) then
			print("warn:", generateWarning(token, "the variable \"" .. name .. "\" is already defined in that scope"));
		else
			print("warn:", string.format("a variable with the name \"%s\" was already defined", name));
		end
		
		-- Có thể trả về id hiện tại nếu muốn.
	end
	
	table.insert(self.variables, name);
	local id = #self.variables;
	-- Lưu ý: Không cập nhật self.variablesLookup
	return id;
end

--------------------------------------------------------------------------------
-- Thêm biến nếu chưa tồn tại tại vị trí id.
-- @param id: id của biến cần kiểm tra.
-- @return: id của biến (sau khi đảm bảo tồn tại).
--------------------------------------------------------------------------------
function Scope:addIfNotExists(id)
	if(not self.variables[id]) then
		local name = string.format("%s%i", config.IdentPrefix, next_name_i);
		next_name_i = next_name_i + 1;
		self.variables[id] = name;
		self.variablesLookup[name] = id;
	end
	return id;
end

--------------------------------------------------------------------------------
-- Kiểm tra xem biến có tên cho trước có tồn tại trong scope hay không.
-- Nếu là global scope và biến chưa tồn tại, tự động thêm biến.
-- @param name: Tên biến cần kiểm tra.
-- @return: true nếu biến tồn tại, false nếu không.
--------------------------------------------------------------------------------
function Scope:hasVariable(name)
	if(self.isGlobal) then
		if self.variablesLookup[name] == nil then
			self:addVariable(name);
		end
		return true;
	end
	return self.variablesLookup[name] ~= nil;
end

--------------------------------------------------------------------------------
-- Trả về danh sách tất cả các biến đã được khai báo trong scope.
-- @return: Mảng tên các biến.
--------------------------------------------------------------------------------
function Scope:getVariables()
	return self.variables;
end

--------------------------------------------------------------------------------
-- Đặt số lượng tham chiếu của biến với id cho trước về 0.
-- @param id: id của biến.
--------------------------------------------------------------------------------
function Scope:resetReferences(id)
	self.referenceCounts[id] = 0;
end

--------------------------------------------------------------------------------
-- Lấy số lượng tham chiếu hiện tại của biến với id cho trước.
-- @param id: id của biến.
-- @return: Số lượng tham chiếu (mặc định 0 nếu chưa có).
--------------------------------------------------------------------------------
function Scope:getReferences(id)
	return self.referenceCounts[id] or 0;
end

--------------------------------------------------------------------------------
-- Giảm số lượng tham chiếu của biến với id cho trước.
-- @param id: id của biến.
--------------------------------------------------------------------------------
function Scope:removeReference(id)
	self.referenceCounts[id] = (self.referenceCounts[id] or 0) - 1;
end

--------------------------------------------------------------------------------
-- Tăng số lượng tham chiếu của biến với id cho trước.
-- @param id: id của biến.
--------------------------------------------------------------------------------
function Scope:addReference(id)
	self.referenceCounts[id] = (self.referenceCounts[id] or 0) + 1;
end

--------------------------------------------------------------------------------
-- Giải quyết (resolve) tên biến trong scope hiện hành hoặc scope cha.
-- Nếu biến không tồn tại ở scope hiện tại, đệ quy lên scope cha.
-- @param name: Tên biến cần giải quyết.
-- @return: Scope và id của biến.
--------------------------------------------------------------------------------
function Scope:resolve(name)
	if(self:hasVariable(name)) then
		return self, self.variablesLookup[name];
	end
	-- Nếu không tìm thấy, đảm bảo có scope cha (global scope phải tồn tại).
	assert(self.parentScope, "No Global Variable Scope was Created! This should not be Possible!");
	-- Đệ quy tìm biến ở scope cha.
	local scope, id = self.parentScope:resolve(name);
	-- Cập nhật số lượng tham chiếu từ scope con lên scope cha.
	self:addReferenceToHigherScope(scope, id, nil, true);
	return scope, id;
end

--------------------------------------------------------------------------------
-- Giải quyết biến theo cách bắt buộc trả về global scope.
-- @param name: Tên biến cần giải quyết.
-- @return: Global scope và id của biến.
--------------------------------------------------------------------------------
function Scope:resolveGlobal(name)
	if(self.isGlobal and self:hasVariable(name)) then
		return self, self.variablesLookup[name];
	end
	assert(self.parentScope, "No Global Variable Scope was Created! This should not be Possible!");
	local scope, id = self.parentScope:resolveGlobal(name);
	self:addReferenceToHigherScope(scope, id, nil, true);
	return scope, id;
end

--------------------------------------------------------------------------------
-- Trả về tên của biến dựa trên id.
-- Hàm này được sử dụng khi cần chuyển đổi lại AST thành mã nguồn.
-- @param id: id của biến.
-- @return: Tên của biến.
--------------------------------------------------------------------------------
function Scope:getVariableName(id)
	return self.variables[id];
end

--------------------------------------------------------------------------------
-- Xóa một biến khỏi scope.
-- @param id: id của biến cần xóa.
--------------------------------------------------------------------------------
function Scope:removeVariable(id)
	local name = self.variables[id];
	self.variables[id] = nil;
	self.variablesLookup[name] = nil;
	self.skipIdLookup[id] = true;
end

--------------------------------------------------------------------------------
-- Thêm một scope con vào scope hiện tại.
-- Đồng thời cập nhật các tham chiếu từ scope con lên các scope cao hơn.
-- @param scope: Scope con cần thêm.
--------------------------------------------------------------------------------
function Scope:addChild(scope)
	-- Cập nhật tham chiếu từ scope con lên scope hiện tại.
	for higherScope, ids in pairs(scope.variablesFromHigherScopes) do
		for id, count in pairs(ids) do
			if count and count > 0 then
				self:addReferenceToHigherScope(higherScope, id, count);
			end
		end
	end
	table.insert(self.children, scope);
end

--------------------------------------------------------------------------------
-- Xóa sạch tất cả các số liệu tham chiếu trong scope hiện tại.
--------------------------------------------------------------------------------
function Scope:clearReferences()
	self.referenceCounts = {};
	self.variablesFromHigherScopes = {};
end

--------------------------------------------------------------------------------
-- Loại bỏ một scope con khỏi danh sách children.
-- @param child: Scope con cần loại bỏ.
-- @return: Scope con đã bị loại bỏ.
--------------------------------------------------------------------------------
function Scope:removeChild(child)
	for i, v in ipairs(self.children) do
		if(v == child) then
			-- Cập nhật lại các tham chiếu từ scope con khi loại bỏ.
			for higherScope, ids in pairs(v.variablesFromHigherScopes) do
				for id, count in pairs(ids) do
					if count and count > 0 then
						self:removeReferenceToHigherScope(higherScope, id, count);
					end
				end
			end
			return table.remove(self.children, i);
		end
	end
end

--------------------------------------------------------------------------------
-- Trả về số lượng biến (id lớn nhất) trong scope.
-- @return: Số lượng biến hiện tại.
--------------------------------------------------------------------------------
function Scope:getMaxId()
	return #self.variables;
end

--------------------------------------------------------------------------------
-- Thêm số lượng tham chiếu của biến với id từ scope con lên scope hiện tại.
-- @param scope: Scope của biến tham chiếu.
-- @param id: id của biến.
-- @param n: Số lượng tham chiếu cần thêm (mặc định là 1).
-- @param b: Cờ cho biết có dừng đệ quy lên scope cha hay không.
--------------------------------------------------------------------------------
function Scope:addReferenceToHigherScope(scope, id, n, b)
	n = n or 1;
	if self.isGlobal then
		-- Nếu scope hiện tại là global nhưng biến thuộc scope không phải global.
		if not scope.isGlobal then
			gg.alert(string.format("Không thể giải quyết Phạm vi \"%s\"", scope.name))
		end
		return;
	end
	if scope == self then
		-- Nếu biến thuộc scope hiện tại, cập nhật trực tiếp số lượng tham chiếu.
		self.referenceCounts[id] = (self.referenceCounts[id] or 0) + n;
		return;
	end
	-- Nếu chưa có thông tin tham chiếu từ scope con lên, khởi tạo bảng mới.
	if not self.variablesFromHigherScopes[scope] then
		self.variablesFromHigherScopes[scope] = {};
	end
	local scopeReferences = self.variablesFromHigherScopes[scope];
	if scopeReferences[id] then
		scopeReferences[id]  = scopeReferences[id] + n;
	else
		scopeReferences[id] = n;
	end
	-- Nếu cờ b chưa được đặt, tiếp tục thêm tham chiếu lên scope cha.
	if not b then
		self.parentScope:addReferenceToHigherScope(scope, id, n);
	end
end

--------------------------------------------------------------------------------
-- Giảm số lượng tham chiếu của biến với id từ scope con lên scope hiện tại.
-- @param scope: Scope của biến tham chiếu.
-- @param id: id của biến.
-- @param n: Số lượng tham chiếu cần giảm (mặc định là 1).
-- @param b: Cờ cho biết có dừng đệ quy hay không.
--------------------------------------------------------------------------------
function Scope:removeReferenceToHigherScope(scope, id, n, b)
	n = n or 1;
	if self.isGlobal then
		return;
	end
	if scope == self then
		self.referenceCounts[id] = (self.referenceCounts[id] or 0) - n;
		return;
	end
	if not self.variablesFromHigherScopes[scope] then
		self.variablesFromHigherScopes[scope] = {};
	end
	local scopeReferences = self.variablesFromHigherScopes[scope];
	if scopeReferences[id] then
		scopeReferences[id]  = scopeReferences[id] - n;
	else
		scopeReferences[id] = 0;
	end
	if not b then
		self.parentScope:removeReferenceToHigherScope(scope, id, n);
	end
end

--------------------------------------------------------------------------------
-- Đổi tên các biến trong scope (và các scope con) nhằm tránh xung đột với các từ khóa.
-- @param settings: Một bảng cài đặt chứa:
--     - Keywords: Danh sách các tên biến không được phép.
--     - generateName(id, scope, originalName): Hàm tạo tên mới dựa trên id, scope và tên gốc.
--     - prefix: (Tùy chọn) Tiền tố cho tên mới.
--------------------------------------------------------------------------------
function Scope:renameVariables(settings)
	if(not self.isGlobal) then
		local prefix = settings.prefix or "";
		local forbiddenNamesLookup = {};
		-- Xây dựng bảng các tên bị cấm từ danh sách từ khóa.
		for _, keyword in pairs(settings.Keywords) do
			forbiddenNamesLookup[keyword] = true;
		end
		
		-- Thêm các tên biến từ các scope cao hơn đã được tham chiếu.
		for scope, ids in pairs(self.variablesFromHigherScopes) do
			for id, count in pairs(ids) do
				if count and count > 0 then
					local name = scope:getVariableName(id);
					forbiddenNamesLookup[name] = true;
				end
			end
		end
		
		-- Đặt lại bảng tra cứu biến.
		self.variablesLookup = {};
		
		local i = 0;
		-- Duyệt qua tất cả các biến trong scope hiện tại.
		for id, originalName in pairs(self.variables) do
			if(not self.skipIdLookup[id] and (self.referenceCounts[id] or 0) >= 0) then
				local name;
				-- Sinh tên mới cho biến cho đến khi tên không bị cấm.
				repeat
					name = prefix .. settings.generateName(i, self, originalName);
					if name == nil then
						name = originalName;
					end
					i = i + 1;
				until not forbiddenNamesLookup[name];

				-- Cập nhật tên biến và bảng tra cứu.
				self.variables[id] = name;
				self.variablesLookup[name] = id;
			end
		end
	end
	
	-- Gọi đệ quy đổi tên cho tất cả các scope con.
	for _, scope in pairs(self.children) do
		scope:renameVariables(settings);
	end
end

return Scope;

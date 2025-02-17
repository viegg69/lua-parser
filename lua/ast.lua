--[[
parser.base.ast returns the BaseAST root of all AST nodes
TODO ...
... nhưng parser.lua.ast (và có thể là parser.grammar.ast) trả về một tập hợp các nút, được khóa vào mã thông báo ... hmm ...
có lẽ để thống nhất, tôi nên để parser.lua.ast trả về LuaAST, là con của BaseAST và là cha của tất cả các nút Lua AST ...
... và cung cấp cho nút đó một thành viên htat giữ bản đồ khóa/giá trị cho tất cả các nút trên mỗi mã thông báo ...
Nhưng sử dụng không gian tên chắc chắn là tiện lợi, đặc biệt là với tất cả các lớp con thành viên và phương thức đi kèm trong đó (traverse, nodeclass, v.v.)
... mặc dù chúng có thể dễ dàng biến thành các trường thành viên và phương thức thành viên

thử thay thế không gian tên 'ast' chỉ bằng chính LuaAST và giữ nguyên quy ước rằng các khóa bắt đầu bằng `_` là các lớp con...
--]]
--local table = require 'ext.table'
--local assert = require 'ext.assert'
--local tolua = require 'ext.tolua'
--local bit = require 'parser.lua.op'
local BaseAST = require 'parser.base.ast'

-- namespace table of all Lua AST nodes
-- TODO get rid of parser's dependency on this?  or somehow make the relation between parser rules and ast's closer, like generate the AST from the parser-rules?
-- another TODO how about just storing subclasses as `._type` , then the 'ast' usage outside this file can be just echanged with LuaASTNode itself, and the file can return a class, and lots of things can be simplified
local ast = {}

-- Lua-specific parent class.  root of all other ast node classes in this file.
local LuaAST = BaseAST:subclass()
-- assign to 'ast.node' to define it as the Lua ast's parent-most node class
ast.node = LuaAST

--[[
args:
	maintainSpan = set to true to have the output maintain the input's span
--]]
local slashNByte = ('\n'):byte()
function LuaAST:serializeRecursiveMember(field, args)
	local maintainSpan
	local prettyPrint
	local TAB = ' '
	if args and (args.maintainSpan or args.prettyPrint) then
		maintainSpan, prettyPrint = true, true
		ast.SPACE = '\n';
		ast.TAB = '\t';
		TAB=''
	end
	local s = ''
	-- :serialize() impl được cung cấp bởi các lớp con
	-- :serialize() nên gọi duyệt theo thứ tự phân tích cú pháp (tại sao tôi muốn làm cho nó tự động và liên kết với trình phân tích cú pháp và ngữ pháp và các lớp nút ast được tạo theo quy tắc)
	-- điều đó có nghĩa là bản thân serialize() không bao giờ nên gọi serialize() mà chỉ gọi hàm consume() được truyền vào nó (vì mục đích mô-đun)
	-- nó có thể có nghĩa là tôi cũng nên nắm bắt tất cả các nút, ngay cả những nút cố định, như từ khóa và ký hiệu, vì mục đích lắp ráp lại cú pháp
	local line = 1
	local col = 1
	local index = 1
	local consume
	local lastspan
	consume = function(x, tab)
		if type(x) == 'number' then
			x = tostring(x)
		end
		if type(x) == 'string' then
			-- đây là chuỗi nối duy nhất của chúng ta
			local function append(u)
				for i=1,#u do
					if u:byte(i) == slashNByte then
						col = 1
						line = line + 1
					else
						col = col + 1
					end
				end
				index = index + #u
				s = s .. u
			end

			-- TODO ở đây nếu bạn muốn ... thêm dòng và cột cho đến khi chúng ta khớp với vị trí ban đầu (hoặc vượt quá vị trí đó)
            -- để thực hiện điều đó, hãy theo dõi các chuỗi được thêm vào để có bộ đếm dòng/cột đang chạy giống như chúng ta làm trong trình phân tích cú pháp
            -- để thực hiện điều đó, hãy tách riêng updatelinecol() trong trình phân tích cú pháp để hoạt động bên ngoài trình đọc dữ liệu
			--[[if maintainSpan and lastspan then
				while line < lastspan.from.line do
					append'\n'
				end
			end]]
			
			

			-- nếu chúng ta có một tên sắp tới, chỉ chèn một khoảng trắng nếu chúng ta đã có một tên
			local namelhs = s:sub(-1):match'[_%w]'
			local namerhs = x:sub(1,1):match'[_%w]'
			if namelhs and namerhs then
				append(' ');--' ';
			elseif not namelhs and not namerhs then
				-- TODO ở đây để thu nhỏ nếu bạn muốn
				-- nếu chúng ta có một ký hiệu sắp xuất hiện, chỉ chèn một khoảng trắng nếu chúng ta đã ở một ký hiệu và hai ký hiệu đó kết hợp lại sẽ tạo ra một ký hiệu hợp lệ khác
				-- bạn sẽ cần phải tìm kiếm lại # độ dài tối đa của bất kỳ ký hiệu nào ...
				append(TAB);--' ';
			end
			append(x)
		elseif type(x) == 'table' then
			lastspan = x.span
			--assert.is(x, BaseAST)
			--assert.index(x, field)
			x[field](x, consume)
		else
			error('here with unknown type '..type(x))
		end
	end
	self[field](self, consume)
	return s
end

-- ok maybe it's not such a good idea to use tostring and serialization for the same purpose ...
LuaAST.__tostring = string.nametostring
ast.SPACE = '';
ast.TAB = '';
ast.CONFIG = {
    prettyPrint = true
}

function LuaAST:toLua(args)
	return self:serializeRecursiveMember('toLua_recursive', args or ast.CONFIG)
end


-- tại sao lại phân biệt toLua() và serialize(consume)?
-- Nhu cầu về thiết kế này xuất hiện nhiều hơn ở các lớp con.
-- serialize(consume) được sử dụng bởi tất cả các ngôn ngữ tuần tự hóa
-- toLua_recursive(consume) dành cho tuần tự hóa dành riêng cho Lua (sẽ được phân lớp con)
-- Tôi không chắc liệu điều này có tốt hơn việc chỉ sử dụng một bảng hoàn toàn riêng biệt các hàm tuần tự hóa cho mỗi nút hay không ...
-- toLua() là API bên ngoài
function LuaAST:toLua_recursive(consume)
	return self:serialize(consume)
end


function LuaAST:exec(...)
	local code = self:toLua()
	local f, msg = load(code, ...)
	if not f then
		return nil, msg, code
	end
	return f
end


-- TODO cách linh hoạt hơn để lặp qua tất cả các trường con là gì?
-- và cách linh hoạt hơn để xây dựng lớp con nút AST và chỉ định các trường của chúng là gì,
-- đặc biệt là với cấu trúc quy tắc ngữ pháp?
-- ... tại sao không lập chỉ mục cho tất cả các trường, sau đó đối với một số lớp nhất định, hãy đặt cho chúng các bí danh vào các trường?
-- ... tương tự với htmlparser?
-- sau đó theo hướng này, các trường sẽ trỏ đến các nút hoặc trỏ đến các bảng đến các nút?
-- hoặc có lẽ các bảng-của-các-nút tự chúng phải là các nút AST?
local fields = {
	{'name', 'field'},
	{'index', 'field'},
	{'value', 'field'},
	{'cond', 'one'},
	{'var', 'one'},
	{'min', 'one'},
	{'max', 'one'},
	{'step', 'one'},
	{'func', 'one'},		-- đây có phải là _function hay là chuỗi mô tả một hàm không?
	{'arg', 'one'},
	{'key', 'one'},
	{'expr', 'one'},
	{'stmt', 'one'},
	{'args', 'many'},
	{'exprs', 'many'},
	{'elseifs', 'many'},
	{'elsestmt', 'many'},
	{'vars', 'many'},
}

ast.exec = LuaAST.exec

--[[
Tôi cần sửa lỗi này tốt hơn để xử lý việc đoản mạch, thay thế, xóa, v.v...
parentFirstCallback là phương thức duyệt parent-first
childFirstCallback là phương thức duyệt child-first
trả về giá trị nào của các lệnh gọi lại mà bạn muốn
trả về một nút mới tại lệnh gọi lại parent sẽ không duyệt các nút con mới tiếp theo của nó được thêm vào cây
--]]
local function traverseRecurse(
	node,
	parentFirstCallback,
	childFirstCallback,
	parentNode
)
	if not LuaAST:isa(node) then return node end
	if parentFirstCallback then
		local ret = parentFirstCallback(node, parentNode)
		if ret ~= node then
			return ret
		end
	end
	if type(node) == 'table' then
		-- treat the object itself like an array of many
		for i=1,#node do
			node[i] = traverseRecurse(node[i], parentFirstCallback, childFirstCallback, node)
		end
		for _,field in ipairs(fields) do
			local name = field[1]
			local howmuch = field[2]
			if node[name] then
				if howmuch == 'one' then
					node[name] = traverseRecurse(node[name], parentFirstCallback, childFirstCallback, node)
				elseif howmuch == 'many' then
					local value = node[name]
					for i=#value,1,-1 do
						value[i] = traverseRecurse(value[i], parentFirstCallback, childFirstCallback, node)
					end
				elseif howmuch == 'field' then
				else
					error("unknown howmuch "..howmuch)
				end
			end
		end
	end
	if childFirstCallback then
		node = childFirstCallback(node, parentNode)
	end
	return node
end

function ast.refreshparents(node)
	traverseRecurse(node, function(node, parent)
		node.parent = parent
		return node
	end)
end

local function traverse(node, ...)
	local newnode = traverseRecurse(node, ...)
	ast.refreshparents(newnode)
	return newnode
end

LuaAST.traverse = traverse
ast.traverse = traverse

function LuaAST.copy(n)
	local newn = {}
	setmetatable(newn, getmetatable(n))
	for i=1,#n do
		newn[i] = LuaAST.copy(n[i])
	end
	for _,field in ipairs(fields) do
		local name = field[1]
		local howmuch = field[2]
		local value = n[name]
		
		if value then
			if howmuch == 'one' then
				if type(value) == 'table' then
					newn[name] = LuaAST.copy(value)
				else
					newn[name] = value
				end
			elseif howmuch == 'many' then
				local newmany = {}
				for k,v in ipairs(value) do
					if type(v) == 'table' then
						newmany[k] = LuaAST.copy(v)
					else
						newmany[k] = v
					end
				end
				newn[name] = newmany
			elseif howmuch == 'field' then
				newn[name] = value
			else
				error("unknown howmuch "..howmuch)
			end
		end
	end
	return newn
end
ast.copy = LuaAST.copy

--[[
làm phẳng một hàm:
đối với tất cả các lệnh gọi của nó, hãy chèn chúng dưới dạng các câu lệnh bên trong hàm
điều này chỉ khả thi nếu các hàm được gọi có dạng cụ thể...
varmap là ánh xạ từ tên hàm đến các đối tượng _function để nội tuyến tại vị trí _call

nếu hàm lồng nhau kết thúc bằng return ...
... thì hãy chèn các khai báo của nó (để ánh xạ lại var) vào một câu lệnh ngay trước câu lệnh có lệnh gọi này
... và gói nội dung return của chúng ta trong dấu ngoặc đơn ... hoặc sử dụng chung () ở mọi nơi (để giải quyết thứ tự)
f stmt
f stmt
f stmt
return something(g(...), h(...))

becomes

f stmt
f stmt
f stmt
local g ret
g stmt
g stmt
g stmt
g ret = previous return value of h
local h ret
h stmt
h stmt
h stmt
h ret = previous return value of h
return something(g ret, h ret)

--]]
function LuaAST.flatten(f, varmap)
	f = LuaAST.copy(f)
	traverseRecurse(f, function(n)
		if type(n) == 'table'
		and ast._call:isa(n)
		then
			local funcname = n.func:toLua()	-- in case it's a var ... ?
			assert(funcname, "can't flatten a function with anonymous calls")
			local f = varmap[funcname]
			if f
			and #f == 1
			and ast._return:isa(f[1])
			then
				local retexprs = {}
				for i,e in ipairs(f[1].exprs) do
					retexprs[i] = LuaAST.copy(e)
					traverseRecurse(retexprs[i], function(v)
						-- _arg is not used by parser - externally used only - I should move flatten somewhere else ...
						if ast._arg:isa(v) then
							return LuaAST.copy(n.args[i])
						end
					end)
					retexprs[i] = ast._par(retexprs[i])
				end
				return ast._block(table.unpack(retexprs))	-- TODO exprlist, and redo assign to be based on vars and exprs
			end
		end
		return n
	end)
	return f
end
ast.flatten = LuaAST.flatten

local function tabs(i, tab)
    return string.rep(ast.TAB, i or 0);
end
local function newline(tab)
    return tab and (ast.SPACE .. tabs(tab)) or ast.SPACE
end
local newtab = -1
local function consumeconcat(consume, t, sep, tab)
	for i,x in ipairs(t) do
		consume(x)
		if sep and sep:find('\n') and i == #t then
		    newtab = newtab - 1
		    consume(newline(newtab))
		    newtab = newtab + 1
		elseif sep and i < #t then
			consume(sep)
		end
	end
end

local function spacesep(stmts, consume, tab)
	newtab = newtab + 1
	if newtab > 0 then
	    consume(newline(newtab));
	end
	consumeconcat(consume, stmts, newline(newtab))
	newtab = newtab - 1
end

local function commasep(exprs, consume)
	consumeconcat(consume, exprs, ',')
end

local function nodeclass(type, parent, args)
	parent = parent or LuaAST
	local cl = parent:subclass(args)
	cl.type = type
	cl.__name = type
	ast['_'..type] = cl
	return cl
end
ast.nodeclass = nodeclass

-- helper function
local function isLuaName(s)
	return s:match'^[_%a][_%w]*$'
end
function ast.keyIsName(key, parser)
	return ast._string:isa(key)
	-- if key is a string and has no funny chars
	and isLuaName(key.value)
	and (
		-- ... and if we don't have a .parser assigned (as is the case of some dynamic ast manipulation ... *cough* vec-lua *cough* ...)
		not parser
		-- ... or if we do have a parser and this name isn't a keyword in the parser's tokenizer
		or not parser.t.keywords[key.value]
	)
end

-- generic global stmt collection
local _block = nodeclass'block'
function _block:init(...)
	for i=1,select('#', ...) do
		self[i] = select(i, ...)
	end
	self.scope = self.scope or nil
end
function _block:serialize(consume, tab)
	spacesep(self, consume, tab or 0)
end

--statements

local _stmt = nodeclass'stmt'

-- TODO 'vars' and 'exprs' should be nodes themselves ...
local _assign = nodeclass('assign', _stmt)
function _assign:init(vars, exprs)
	self.vars = table(vars)
	self.exprs = table(exprs)
end
function _assign:serialize(consume)
	commasep(self.vars, consume)
	consume'='
	commasep(self.exprs, consume)
end

-- chúng ta có nên áp đặt các ràng buộc xây dựng _do(_block(...))
-- hay chúng ta nên suy ra? _do(...) = {type = 'do', block = {type = 'block, ...}}
-- hay chúng ta không nên làm cả hai? _do(...) = {type = 'do', ...}
-- không làm gì cả vào lúc này
-- nhưng điều đó có nghĩa là _do và _block giống hệt nhau ...
local _do = nodeclass('do', _stmt)
function _do:init(...)
	for i=1,select('#', ...) do
		self[i] = select(i, ...)
	end
end
function _do:serialize(consume)
	consume'do'
	spacesep(self, consume)
	consume'end'
end

local _while = nodeclass('while', _stmt)
-- TODO just make self[1] into the cond ...
function _while:init(cond, ...)
	self.cond = cond
	for i=1,select('#', ...) do
		self[i] = select(i, ...)
	end
end
function _while:serialize(consume)
	consume'while'
	consume(self.cond)
	consume'do'
	spacesep(self, consume)
	consume'end'
end

local _repeat = nodeclass('repeat', _stmt)
-- TODO just make self[1] into the cond ...
function _repeat:init(cond, ...)
	self.cond = cond
	for i=1,select('#', ...) do
		self[i] = select(i, ...)
	end
end
function _repeat:serialize(consume)
	consume'repeat'
	spacesep(self, consume)
	consume'until'
	consume(self.cond)
end

--[[
_if(_eq(a,b),
	_assign({a},{2}),
	_elseif(...),
	_elseif(...),
	_else(...))
--]]
-- weird one, idk how to reformat
local _if = nodeclass('if', _stmt)
-- TODO maybe just assert the node types and store them as-is in self[i]
function _if:init(cond,...)
	local elseifs = table()
	local elsestmt, laststmt
	for i=1,select('#', ...) do
		local stmt = select(i, ...)
		if ast._elseif:isa(stmt) then
			elseifs:insert(stmt)
		elseif ast._else:isa(stmt) then
			assert(not elsestmt)
			elsestmt = stmt -- and remove
		else
			if laststmt then
				assert(laststmt.type ~= 'elseif' and laststmt.type ~= 'else', "got a bad stmt in an if after an else: "..laststmt.type)
			end
			table.insert(self, stmt)
		end
		laststmt = stmt
	end
	self.cond = cond
	self.elseifs = elseifs
	self.elsestmt = elsestmt
end
function _if:serialize(consume)
	consume'if'
	consume(self.cond)
	consume'then'
	spacesep(self, consume)
	for _,ei in ipairs(self.elseifs) do
		consume(ei)
	end
	if self.elsestmt then
		consume(self.elsestmt)
	end
	consume'end'
end

-- aux for _if
local _elseif = nodeclass('elseif', _stmt)
-- TODO just make self[1] into the cond ...
function _elseif:init(cond,...)
	self.cond = cond
	for i=1,select('#', ...) do
		self[i] = select(i, ...)
	end
end
function _elseif:serialize(consume)
	consume'elseif'
	consume(self.cond)
	consume'then'
	spacesep(self, consume)
end

-- aux for _if
local _else = nodeclass('else', _stmt)
function _else:init(...)
	for i=1,select('#', ...) do
		self[i] = select(i, ...)
	end
end
function _else:serialize(consume)
	consume'else'
	spacesep(self, consume)
end

local _foreq = nodeclass('foreq', _stmt)
-- step is optional
-- TODO just make self[1..4] into the var, min, max, step ...
-- ... this means we can possibly have a nil child mid-sequence ...
-- .. hmm ...
-- ... which is better:
-- *) requiring table.max for integer iteration instead of ipairs
-- *) or using fields instead of integer indexes?
function _foreq:init(var,min,max,step,...)
	self.var = var
	self.min = min
	self.max = max
	self.step = step
	for i=1,select('#', ...) do
		self[i] = select(i, ...)
	end
end
function _foreq:serialize(consume)
	consume'for'
	consume(self.var)
	consume'='
	consume(self.min)
	consume','
	consume(self.max)
	if self.step then
		consume','
		consume(self.step)
	end
	consume'do'
	spacesep(self, consume)
	consume'end'
end

-- TODO 'vars' should be a node itself
local _forin = nodeclass('forin', _stmt)
function _forin:init(vars, iterexprs, ...)
	self.vars = vars
	self.iterexprs = iterexprs
	for i=1,select('#', ...) do
		self[i] = select(i, ...)
	end
end
function _forin:serialize(consume)
	consume'for'
	commasep(self.vars, consume)
	consume'in'
	commasep(self.iterexprs, consume)
	consume'do'
	spacesep(self, consume)
	consume'end'
end

local _function = nodeclass('function', _stmt)
-- name is optional
-- TODO make 'args' a node
function _function:init(name, args, ...)
	-- prep args...
	for i=1,#args do
		args[i].index = i
		args[i].param = true
	end
	self.name = name
	self.args = args
	for i=1,select('#', ...) do
		self[i] = select(i, ...)
	end
end
function _function:serialize(consume)
	consume'function'
	if self.name then
		consume(self.name)
	end
	consume'('
	commasep(self.args, consume)
	consume')'
	spacesep(self, consume)
	consume'end'
end

-- aux for _function
-- not used by parser - externally used only - I should get rid of it
local _arg = nodeclass'arg'
-- TODO just self[1] ?
function _arg:init(index)
	self.index = index
end
-- params need to know what function they're in
-- so they can reference the function's arg names
function _arg:serialize(consume)
	consume('arg'..self.index)
end

-- _local có thể là phép gán nhiều biến cho nhiều biểu thức
-- hoặc tùy chọn có thể là khai báo nhiều biến không có câu lệnh
-- vì vậy nó sẽ có dạng phép gán
-- nhưng nó cũng có thể là khai báo hàm đơn không có ký hiệu bằng ...
-- trình phân tích cú pháp phải chấp nhận các hàm và biến là các điều kiện riêng biệt
-- Tôi cũng muốn tách chúng thành các ký hiệu riêng biệt ở đây ...
-- exprs là một bảng chứa: 1) một hàm đơn 2) một câu lệnh gán đơn 3) một danh sách các biến
local _local = nodeclass('local', _stmt)
-- TODO just self[1] instead of self.exprs[i]
function _local:init(exprs)
	if ast._function:isa(exprs[1]) or ast._assign:isa(exprs[1]) then
		assert(#exprs == 1, "local functions or local assignments must be the only child")
	end
	self.exprs = table(assert(exprs))
end
function _local:serialize(consume)
	if ast._function:isa(self.exprs[1]) or ast._assign:isa(self.exprs[1]) then
		consume'local'
		consume(self.exprs[1])
	else
		consume'local'
		commasep(self.exprs, consume)
	end
end

-- control

local _return = nodeclass('return', _stmt)
-- TODO either 'exprs' a node of its own, or flatten it into 'return'
function _return:init(...)
	self.exprs = {...}
end
function _return:serialize(consume)
	consume'return'
	commasep(self.exprs, consume)
end

local _break = nodeclass('break', _stmt)
function _break:serialize(consume) consume'break' end

local _call = nodeclass'call'
-- TODO 'args' a node of its own ?  or store it in self[i] ?
function _call:init(func, ...)
	self.func = func
	self.args = {...}
end
function _call:serialize(consume)
	if #self.args == 1
	and (ast._table:isa(self.args[1])
		or ast._string:isa(self.args[1])
	) then
		consume(self.func)
		consume(self.args[1])
	else
		consume(self.func)
		consume'('
		commasep(self.args, consume)
		consume')'
	end
end

local _nil = nodeclass'nil'
_nil.const = true
function _nil:serialize(consume) consume'nil' end

local _boolean = nodeclass'boolean'

local _true = nodeclass('true', _boolean)
_true.const = true
_true.value = true
function _true:serialize(consume) consume'true' end

local _false = nodeclass('false', _boolean)
_false.const = true
_false.value = false
function _false:serialize(consume) consume'false' end

local _number = nodeclass'number'
-- TODO just self[1] instead of self.value ?
-- but this breaks convention with _boolean having .value as its static member value.
-- I could circumvent this with _boolean subclass [1] holding the value ...
function _number:init(value) self.value = value end
function _number:serialize(consume) consume(tostring(self.value)) end

local _string = nodeclass'string'
-- TODO just self[1] instead of self.value
function _string:init(value) self.value = value end
function _string:serialize(consume)
	-- use ext.tolua's string serializer
	consume(tolua(self.value))
end

local _vararg = nodeclass'vararg'
function _vararg:serialize(consume) consume((ast.TAB == '' and '' or ' ') .. '...' .. (ast.TAB == '' and '' or ' ')) end

-- TODO 'args' a node, or flatten into self[i] ?
local _table = nodeclass'table'	-- single-element assigns
function _table:init(...)
	for i=1,select('#', ...) do
		self[i] = select(i, ...)
	end
end

function _table:serialize(consume)
	newtab = newtab + 1
	consume'{'
	if #self > 2 then
	    consume(newline(newtab));
	elseif newtab > 2 then
	    consume(newline(newtab));
	end
	for i,arg in ipairs(self) do
		-- if it's an assign then wrap the vars[1] with []'s
		if ast._assign:isa(arg) then
			assert.len(arg.vars, 1)
			assert.len(arg.exprs, 1)
			-- TODO if it's a string and name and not a keyword then use our shorthand
			-- but for this , I should put the Lua keywords in somewhere that both the AST and Tokenizer can see them
			-- and the Tokenizer builds separate lists depending on the version (so I guess a table per version?)
			if ast.keyIsName(arg.vars[1], self.parser) then
				consume(arg.vars[1].value)
			else
				consume'['
				consume(arg.vars[1])
				consume']'
			end
			consume'='
			consume(arg.exprs[1])
		else
			consume(arg)
		end
		if i < #self then
			consume','
		end
	end
	newtab = newtab - 1
	if #self > 2 then
	    consume(newline(newtab));
	elseif newtab > 2 then
	    consume(tabs());
	end
	consume'}'
end

-- OK, đây là ví dụ kinh điển về lợi ích của trường so với số nguyên:
-- khả năng mở rộng.
-- attrib được thêm vào sau
-- khi chúng ta thêm/xóa trường, điều đó có nghĩa là sắp xếp lại các chỉ mục và điều đó có nghĩa là phá vỡ khả năng tương thích
-- một giải pháp thay thế để hợp nhất cả hai chỉ là các hàm được đặt tên và các con được lập chỉ mục theo số nguyên
-- một giải pháp khác là một quy trình duyệt theo từng con (như :serialize())
local _var = nodeclass'var'	-- variable, lhs of ast._assign's
function _var:init(index, attrib, scope)
	self.index = index
	self.attrib = attrib
	self.scope = self.scope or scope
	--self.name = self.scope:getVariableName(index)
end
function _var:serialize(consume)
	consume(self.index and self.scope:getVariableName(self.index) or self.name)
	if self.attrib then
		-- the extra space is needed for assignments, otherwise lua5.4 `local x<const>=1` chokes while `local x<const> =1` works
		consume'<'
		consume(self.attrib)
		consume'>'
	end
end

local _par = nodeclass'par'
ast._par = _par
ast._parenthesis = nil
function _par:init(expr)
	self.expr = expr
end
function _par:serialize(consume)
	consume'('
	consume(self.expr)
	consume')'
end

local _index = nodeclass'index'
function _index:init(expr,key)
	self.expr = expr
	-- helper add wrappers to some types:
	-- TODO or not?
	if type(key) == 'string' then
		key = ast._string(key)
	elseif type(key) == 'number' then
		key = ast._number(key)
	end
	self.key = key
end
function _index:serialize(consume)
	if ast.keyIsName(self.key, self.parser) then
		-- the use a .$key instead of [$key]
		consume(self.expr)
		consume'.'
		consume(self.key.value)
	else
		consume(self.expr)
		consume'['
		consume(self.key)
		consume']'
	end
end

-- this isn't the () call itself, this is just the : dereference
-- a:b(c) is _call(_indexself(_var'a', _var'b'), _var'c')
-- technically this is a string lookup, however it is only valid as a lua name, so I'm just passing the Lua string itself
local _indexself = nodeclass'indexself'
function _indexself:init(expr,key)
	self.expr = assert(expr)
	assert(isLuaName(key))
	-- TODO compat with _index?  always wrap?  do this before passing in key?
	--key = ast._string(key)
	self.key = assert(key)
end
function _indexself:serialize(consume)
	consume(self.expr)
	consume':'
	consume(self.key)
end


local _op = nodeclass'op'
-- TODO 'args' a node ... or just flatten it into this node ...
function _op:init(...)
	for i=1,select('#', ...) do
		self[i] = select(i, ...)
	end
end
function _op:serialize(consume)
	for i,x in ipairs(self) do
		consume(x)
		if i < #self then consume(self.op) end
	end
end

for _,info in ipairs{
	{'add','+'},
	{'sub','-'},
	{'mul','*'},
	{'div','/'},
	{'pow','^'},
	{'mod','%'},
	{'concat','..'},
	{'lt','<'},
	{'le','<='},
	{'gt','>'},
	{'ge','>='},
	{'eq','=='},
	{'ne','~='},
	{'and','and'},
	{'or','or'},
	{'idiv', '//'},	-- 5.3+
	{'band', '&'},	-- 5.3+
	{'bxor', '~'},	-- 5.3+
	{'bor', '|'},	-- 5.3+
	{'shl', '<<'},	-- 5.3+
	{'shr', '>>'},	-- 5.3+
} do
	local op = info[2]
	local cl = nodeclass(info[1], _op)
	cl.op = op
end

for _,info in ipairs{
	{'unm','-'},
	{'not','not'},
	{'len','#'},
	{'bnot','~'},		-- 5.3+
} do
	local op = info[2]
	local cl = nodeclass(info[1], _op)
	cl.op = op
	function cl:init(...)
		for i=1,select('#', ...) do
			self[i] = select(i, ...)
		end
	end
	function cl:serialize(consume)
		consume(self.op)
		consume(self[1])	-- spaces required for 'not'
	end
end

local _goto = nodeclass('goto', _stmt)
function _goto:init(name)
	self.name = name
end
function _goto:serialize(consume)
	consume'goto'
	consume(self.name)
end

local _label = nodeclass('label', _stmt)
function _label:init(name)
	self.name = name
end
function _label:serialize(consume)
	consume'::'
	consume(self.name)
	consume'::'
end

return ast

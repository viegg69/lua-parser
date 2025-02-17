--local table = require 'ext.table'
--local string = require 'ext.string'
--local class = require 'ext.class'
--local assert = require 'ext.assert'
local DataReader = require 'parser.base.datareader'

local Tokenizer = class()

function Tokenizer:initSymbolsAndKeywords(...)
end

function Tokenizer:init(data, ...)
	-- TODO move what this does to just the subclass initialization
	self.symbols = table(self.symbols)
	self.keywords = table(self.keywords):setmetatable(nil)
	self:initSymbolsAndKeywords(...)

	self.r = DataReader(data)
	self.gettokenthread = function(self)
		local r = self.r
		while true do
			self:skipWhiteSpaces()
			if r:done() then self.gettokenthread, self.nexttoken, self.nexttokentype = nil, nil, nil break end
			
			if self:parseComment() then
			elseif self:parseString() 
			or self:parseName() 
			or self:parseNumber() 
			or self:parseSymbol() 
			then break
			else self.errors = {msg = "unknown token "..r.data:sub(r.index)} return self.errors
			end
			
			if r:done() then self.gettokenthread, self.nexttoken, self.nexttokentype = nil, nil, nil break end
		end
	end
	
end

function Tokenizer:skipWhiteSpaces()
	local r = self.r
	r:canbe'%s+'
---DEBUG(parser.base.tokenizer): if r.lasttoken then print('read space ['..(r.index-#r.lasttoken)..','..r.index..']: '..r.lasttoken) end
end

-- Lua-specific comments (tho changing the comment symbol is easy ...)
Tokenizer.singleLineComment = string.patescape'--'
function Tokenizer:parseComment()
	local r = self.r
	if r:canbe(self.singleLineComment) then
local start = r.index - #r.lasttoken
		-- read block comment if it exists
		if not r:readblock() then
			-- read line otherwise
			if not r:seekpast'\n' then
				r:seekpast'$'
			end
		end
		--local commentstr = r.data:sub(start, r.index-1)
		-- TODO how to insert comments into the AST?  should they be their own nodes?
		-- should all whitespace be its own node, so the original code text can be reconstructed exactly?
		--self.nexttoken, self.nexttokentype = commentstr, 'comment'
---DEBUG(parser.base.tokenizer): print('read comment ['..start..','..(r.index-1)..']:'..commentstr)
		return true
	end
end

function Tokenizer:parseString()
	if self:parseBlockString() then return true end
	if self:parseQuoteString() then return true end
end

-- Lua-specific block strings
function Tokenizer:parseBlockString()
	local r = self.r
	if r:readblock() then
---DEBUG(parser.base.tokenizer): print('read multi-line string ['..(r.index-#r.lasttoken)..','..r.index..']: '..r.lasttoken)
		self.nexttoken, self.nexttokentype = r.lasttoken, 'string'
		return true
	end
end

-- TODO this is a very lua function though it's in parser/base/ and not parser/lua/ ...
-- '' or "" single-line quote-strings with escape-codes
function Tokenizer:parseQuoteString()
	local r = self.r
	if r:canbe'["\']' then
---DEBUG(parser.base.tokenizer): print('read quote string ['..(r.index-#r.lasttoken)..','..r.index..']: '..r.lasttoken)
---DEBUG(parser.base.tokenizer): local start = r.index-#r.lasttoken
		local quote = r.lasttoken
		local s = table()
		while true do
			r:seekpast'.'
			if r.lasttoken == quote then break end
			if r:done() then self.errors = {msg = "unfinished string"} return self.errors end
			if r.lasttoken == '\\' then
				local esc = r:canbe'.'
				local escapeCodes = {a='\a', b='\b', f='\f', n='\n', r='\r', t='\t', v='\v', ['\\']='\\', ['"']='"', ["'"]="'", ['0']='\0', ['\r']='\n', ['\n']='\n'}
				local escapeCode = escapeCodes[esc]
				if escapeCode then
					s:insert(escapeCode)
				elseif esc == 'x' and self.version >= '5.2' then
					esc = r:mustbe'%x' .. r:mustbe'%x'
					s:insert(string.char(tonumber(esc, 16)))
				elseif esc == 'u' and self.version >= '5.3' then
					r:mustbe'{'
					local code = 0
					while true do
						local ch = r:canbe'%x'
						if not ch then break end
						code = code * 16 + tonumber(ch, 16)
					end
					r:mustbe'}'

					-- hmm, needs bit library or bit operations, which should only be present in version >= 5.3 anyways so ...
					local bit = bit32 or require 'bit'
					if code < 0x80 then
						s:insert(string.char(code))	-- 0xxxxxxx
					elseif code < 0x800 then
						s:insert(
							string.char(bit.bor(0xc0, bit.band(0x1f, bit.rshift(code, 6))))
							.. string.char(bit.bor(0x80, bit.band(0x3f, code)))
						)
					elseif code < 0x10000 then
						s:insert(
							string.char(bit.bor(0xe0, bit.band(0x0f, bit.rshift(code, 12))))
							.. string.char(bit.bor(0x80, bit.band(0x3f, bit.rshift(code, 6))))
							.. string.char(bit.bor(0x80, bit.band(0x3f, code)))
						)
					else
						s:insert(
							string.char(bit.bor(0xf0, bit.band(0x07, bit.rshift(code, 18))))
							.. string.char(bit.bor(0x80, bit.band(0x3f, bit.rshift(code, 12))))
							.. string.char(bit.bor(0x80, bit.band(0x3f, bit.rshift(code, 6))))
							.. string.char(bit.bor(0x80, bit.band(0x3f, code)))
						)
					end
				elseif esc:match('%d') then
					-- can read up to three
					if r:canbe'%d' then esc = esc .. r.lasttoken end
					if r:canbe'%d' then esc = esc .. r.lasttoken end
					s:insert(string.char(tonumber(esc)))
				else
					if self.version >= '5.2' then
						-- lua5.1 doesn't care about bad escape codes
						self.errors = {msg = "invalid escape sequence "..esc}
					    return self.errors
					end
				end
			else
				s:insert(r.lasttoken)
			end
		end
---DEBUG(parser.base.tokenizer): print('read quote string ['..start..','..(r.index-#r.lasttoken)..']: '..r.data:sub(start, r.index-#r.lasttoken))
		self.nexttoken, self.nexttokentype = s:concat(), 'string'
		return true
	end
end

-- C names
function Tokenizer:parseName()
	local r = self.r
	if r:canbe'[%a_][%w_]*' then	-- name
---DEBUG(parser.base.tokenizer): print('read name ['..(r.index-#r.lasttoken)..', '..r.index..']: '..r.lasttoken)
		self.nexttoken, self.nexttokentype = r.lasttoken, self.keywords[r.lasttoken] and 'keyword' or 'name'
		return true
	end
end

function Tokenizer:parseNumber()
	local r = self.r
	if r.data:match('^[%.%d]', r.index) -- if it's a decimal or a number...
	and (r.data:match('^%d', r.index)	-- then, if it's a number it's good
	or r.data:match('^%.%d', r.index))	-- or if it's a decimal then if it has a number following it then it's good ...
	then 								-- otherwise I want it to continue to the next 'else'
		-- lua doesn't consider the - to be a part of the number literal
		-- instead, it parses it as a unary - and then possibly optimizes it into the literal during ast optimization
---DEBUG(parser.base.tokenizer): local start = r.index
		if r:canbe'0[xX]' then
			self:parseHexNumber()
		else
			self:parseDecNumber()
		end
---DEBUG(parser.base.tokenizer): print('read number ['..start..', '..r.index..']: '..r.data:sub(start, r.index-1))
		return true
	end
end

function Tokenizer:parseHexNumber()
	local r = self.r
	local token = r:mustbe('[%da-fA-F]+', 'malformed number')
	self.nexttoken, self.nexttokentype = '0x'..token, 'number'
end

function Tokenizer:parseDecNumber()
	local r = self.r
	local token = r:canbe'[%.%d]+'
	assert.le(#token:gsub('[^%.]',''), 1, 'malformed number')
	local n = table{token}
	if r:canbe'e' then
		n:insert(r.lasttoken)
		n:insert(r:mustbe('[%+%-]%d+', 'malformed number'))
	end
	self.nexttoken, self.nexttokentype = n:concat(), 'number'
end

function Tokenizer:parseSymbol()
	local r = self.r
	-- see if it matches any symbols
	for _,symbol in ipairs(self.symbols) do
		if r:canbe(string.patescape(symbol)) then
---DEBUG(parser.base.tokenizer): print('read symbol ['..(r.index-#r.lasttoken)..','..r.index..']: '..r.lasttoken)
			self.nexttoken, self.nexttokentype = r.lasttoken, 'symbol'
			return true
		end
	end
end

-- separate this in case someone has to modify the tokenizer symbols and keywords before starting
function Tokenizer:start()
	-- TODO provide tokenizer the AST namespace and have it build the tokens (and keywords?) here automatically
	self.symbols = self.symbols:mapi(function(v,k) return true, v end):keys()
	-- arrange symbols from largest to smallest
	self.symbols:sort(function(a,b) return #a > #b end)
	self:consume()
	self:consume()
end

function Tokenizer:consume()
	-- [[ TODO store these in an array somewhere, make the history adjustable
	-- then in all the get[prev][2]loc's just pass an index for how far back to search
	self.prev2index = self.previndex
	self.prev2tokenIndex = self.prevtokenIndex

	self.previndex = self.r.index
	self.prevtokenIndex = #self.r.tokenhistory+1
	--]]

	self.token = self.nexttoken
	self.tokentype = self.nexttokentype
	if not self.gettokenthread then
		self.nexttoken = nil
		self.nexttokentype = nil
		-- done = true
		return
	end
	local errs = self:gettokenthread()
	-- detect errors
	if self.errors or errs then
		local err = nexttoken
		error{
			msg = err,
			token = self.token,
			tokentype = self.tokentype,
			pos = self:getpos(),
			traceback = debug.traceback(self.gettokenthread),
		}
	elseif self.r:done() and self.gettokenthread then
	    return
	end
end

function Tokenizer:getpos()
	return 'line '..self.r.line
		..' col '..self.r.col
		..' code "'..self.r.data:sub(self.r.index):match'^[^\n]*'..'"'
end

-- return the span across
function Tokenizer:getloc()
	local r = self.r
	local line = self.r.line
	local col = self.r.col

	return {
		line = line,
		col = col,
		index = self.prev2index,
		tokenIndex = self.prev2tokenIndex,
	}
end

return Tokenizer

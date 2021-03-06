module Main where 
import Data.List
import Data.Maybe
import Data.Char

-------------------------------------------------------------------------------------------------
----------------------------------------------- Parser ------------------------------------------

type Parser symbol result = [symbol]->[([symbol],result)]

charToNum c = (fromInteger.read) [c]

symbol::Char->Parser Char Char
symbol c [] = []
symbol c (x:xs)| x==c = [(xs,c)] 
               | otherwise = []
                             
satisfy::(a->Bool)->Parser a a
satisfy p [] = []
satisfy p (x:xs) | p x = [(xs,x)]
                 | otherwise = []

succeed::a->Parser s a
succeed x l = [(l,x)]


token::Eq a=>[a]->Parser a [a]

token k xs |k==(take n xs) = [((drop n xs),k)]  
           |otherwise = []
            where n = length k

fail xs = []

epsilon = succeed ()

infixr 6 <*>,<*,*>
infixr 5 <@
infixr 4 <|>

(<*>)::Parser s a->Parser s b->Parser s (a,b)
(p1 <*> p2) xs = [(xs2,(v1,v2))|(xs1,v1)<-p1 xs,(xs2,v2)<-p2 xs1]


(<|>)::Parser s a->Parser s a->Parser s a
(p1 <|> p2) xs = p1 xs ++ p2 xs

(<@)::Parser s a -> (a->b)-> Parser s b
(p <@ f) xs = [(xs,f v)|(xs,v)<-p xs] 

(<*)::Parser s a->Parser s b->Parser s a 
p1 <* p2 = p1 <*> p2 <@ fst

(*>)::Parser s a->Parser s b->Parser s b
p1 *> p2 = p1 <*> p2 <@ snd

(<:*>)::Parser s a->Parser s [a]->Parser s [a]
p1 <:*> p2 = p1 <*> p2 <@ listify 

listify (x,xs) = x:xs

zeroOrMore::Parser s a->Parser s [a]
zeroOrMore p =  (p <:*> (zeroOrMore p)) <|> succeed [] 
               
oneOrMore::Parser s a->Parser s [a]
oneOrMore p = p <:*> (zeroOrMore p)

option::Parser s a->Parser s [a]
option p =   succeed [] <|> p <@ f  
            where f x = [x]

(<?@) ::Parser s [a]->(b,(a->b))->Parser s b
p <?@ (no,yes) = p <@ f
                 where f [] = no
                       f [x]= yes x

digit::Parser Char Char
digit = satisfy isDigit 
alpha = satisfy isAlpha 

number::Num a => [Char]->[([Char],a)]
number = ((oneOrMore digit) <@ (fromInteger.read))  

determ p xs | null l = []
            | otherwise = [head l]
                       where l = p xs

greedy = determ.zeroOrMore

sp  = greedy (symbol ' ')

pack s1 p s2 = s1 *> p <* s2

paranthesized p = pack (symbol '(') p (symbol ')')

fractional = oneOrMore digit <@ (foldr f 0.0)
             where f x y = (charToNum x + y)/10


float = (number <*> 
        (option (symbol '.' *> fractional) <?@ (0.0,id))) <@ uncurry (+)
               
listOf p s = p <:*> (zeroOrMore (s *> p)) <|> succeed []

commaList p = listOf p (symbol ',')

spsymbol c = symbol c <* sp
chainr p s = (zeroOrMore (p <*> s)) <*> p <@ uncurry (flip (foldr f))
             where f (x,op) y = x `op` y


chainl p s = p <*> (zeroOrMore (s <*> p)) <@ uncurry (foldl f) 
                    where f x (op,y) = x `op` y 

name = (alpha <:*> greedy (alpha <|> digit)) 

reservedWords = [ "if" , "else" , "null" , "head" , "tail" , "then"]
identifier xs | l==[] = []
              | ((snd (head l)) `elem` reservedWords)=[] 
              | otherwise = l     
                where l = name xs                                         
type Fname = String
type Var = String

data Program = Prog [Fundef] Exp deriving (Show,Eq)
data Fundef = Fun String [String] Exp deriving (Show,Eq)
data Exp = I Int | B Bool | V String | Nil | Fname String | App Exp Exp
           deriving (Show,Eq)                            


---------------------Exp
boolean = (token "True") <@ const True  <|> (token "False") <@ const False  

sqrBracketed p = pack (symbol '[' <* sp)  p (sp *> symbol ']')
commasp = (symbol ',') <* sp
list::Parser Char Exp
list = sqrBracketed((listOf lterm commasp) <@ foldr (\x y-> App (App (Fname "cons") x) y) Nil)



headterm = headtoken *> factor <@ (App (Fname "car")) 
tailterm = tailtoken *> factor <@ (App (Fname "cdr"))

factor::Parser Char Exp
factor = (number <@ I)
         <|>
         (boolean <@ B)
         <|> headterm <|> tailterm
         <|>
         (identifier <@ (\x -> Fname x))
         <|>
         (identifier <@ V)
         <|>list
         <|>paranthesized expr
appterm = chainl (sp *> factor) ((symbol ' ') <@ const (\x y -> App x y))
         

sptoken t = determ (sp *> (token t) <* sp)
headtoken = sptoken "car "
tailtoken = sptoken "cdr "
iftoken = sptoken "if "
thentoken = sptoken "then "
elsetoken =sptoken "else "
eqtoken = sptoken "=="
nulltoken =sptoken "null "
plus = sptoken "+"
minus = sptoken "-"
mult = sptoken "*"
slash = sptoken "/"
constoken = sptoken ":"
feqtoken = sptoken "="

bterm = sp *> (chainl appterm ((mult <@ const (f "*") ) <|> (slash <@ const (f "/") )))
aterm = sp *> (chainl bterm ((plus <@ const (f "+") ) <|> (minus <@ const (f "-") )))
f op = \x y -> App (App (Fname op) x) y 
lterm = sp *> (chainr aterm (constoken <@ const (f "cons")))
              
eqterm = sp*> lterm <*> (eqtoken  *> lterm ) <@ f
         <|> nulltoken  *> lterm <@ (App (Fname "null"))
         <|> lterm
         where f (x,y) = App (App (Fname "==") x) y

ifterm = (iftoken *> eqterm) <*> (thentoken *> expr) <*> (elsetoken *> expr) <@f
         <|> eqterm 
         where f (x1,(x2,x3)) = App (App (App (Fname "if") x1) x2) x3
         
expr=ifterm 

----------------fundefs

fargs = (symbol ' ') *> listOf (identifier) (symbol ' ') <|> succeed []

fundef::Parser Char Fundef                                                   
fundef = identifier <*> fargs  <*> (feqtoken *>  expr)	 <@ f
          where f (x,(y,z)) = Fun x y z
               
               

-- ---------------program

prog::Parser Char Program
prog =  (zeroOrMore (fundef <* (symbol '\n'))) <*>  expr <@f
        where f (x,y) = Prog x y
              
parse pgm = correctProgram (snd (head (prog pgm)))

-- For the expression part in all fundefs, if there exists "Fname argname" such that argname is a parameter name then replace "Fname argname" by "V argname"

correctProgram (Prog defs exp) = Prog (map (fundefCorrect []) defs) exp

fundefCorrect _ (Fun fname par exp) = Fun fname par (fundefCorrectExp par exp)
fundefCorrectExp par (App e1 e2) = App (fundefCorrectExp par e1) (fundefCorrectExp par e2)
fundefCorrectExp par (Fname argname) | argname `elem` par = V argname
                                     | otherwise = Fname argname
fundefCorrectExp _ x = x    

-------------------------------------------------------------------------------------------------
------------------------------------------- Compiler --------------------------------------------

type Code = [Instn]

data Instn	=	PUSH Int | PUSHINT Int | PUSHGLOBAL String |
				PUSHBOOL Bool | PUSHNIL | POP Int |
				EVAL | UNWIND | MKAP | UPDATE Int | RETURN |
				LABEL String | JUMP String | JFALSE String |
				ADD | SUB | MUL | DIV | CONS | HEAD | TAIL | IF | EQU |
				GLOBSTART String Int | PRINT | STOP

instance Show Instn where
	show (PUSH i)			= "    PUSH " ++ show i ++ "\n"
	show (PUSHINT i)		= "    PUSHINT " ++ show i ++ "\n"
	show (PUSHGLOBAL str)	= "    PUSHGLOBAL " ++ show str ++ "\n"
	show (PUSHBOOL i)		= "    PUSH " ++ show i ++ "\n"
	show PUSHNIL			= "    PUSHNIL " ++ "\n"
	show (POP i)			= "    POP " ++ show i ++ "\n"
	show EVAL				= "    EVAL" ++ "\n"
	show UNWIND				= "    UNWIND" ++ "\n"
	show MKAP				= "    MKAP" ++ "\n"
	show RETURN				= "    RETURN" ++ "\n"
	show (UPDATE i)			= "    UPDATE " ++ show i ++ "\n"
	show (LABEL str)		= "LABEL " ++ show str ++ "\n"
	show (JUMP str)			= "    JUMP " ++ show str ++ "\n"
	show (JFALSE str)		= "    JFALSE " ++ show str ++ "\n"
	show ADD				= "    ADD" ++ "\n"
	show SUB				= "    SUB" ++ "\n"
	show MUL				= "    MUL" ++ "\n"
	show DIV				= "    DIV" ++ "\n"
	show CONS				= "    CONS" ++ "\n"
	show HEAD				= "    HEAD" ++ "\n"
	show TAIL				= "    TAIL" ++ "\n"
	show IF					= "    IF" ++ "\n"
	show EQU				= "    EQU" ++ "\n"
	show (GLOBSTART str i)	= "\n GLOBSTART " ++ show str ++ " " ++ show i ++ "\n"
	show PRINT				= "    PRINT" ++ "\n"
	show STOP				= "    STOP" ++ "\n"

gencpgm :: Program -> Code
gencpgm (Prog fs e) = foldr gencfun (gencmain e) fs

gencfun :: Fundef -> Code -> Code
gencfun (Fun fname args body) code = GLOBSTART fname (length args) : 
										expcode body var_position (length args) (unwind_pop args code)
	where var_position name = fromJust (elemIndex name args) + 1

unwind_pop :: [String] -> Code -> Code
unwind_pop [] code = UPDATE 1 : UNWIND : code
unwind_pop args code = UPDATE (length args + 1) : POP (length args) : UNWIND : code

gencmain :: Exp -> Code
gencmain e = LABEL "MAIN" : expcode e (\x -> 0) 0 (EVAL : PRINT : STOP: builtins)

expcode :: Exp ->  (String -> Int) -> Int -> Code -> Code
expcode (App e1 e2) s d code	= expcode e2 s d (expcode e1 s (d + 1) (MKAP : code))
expcode exp s d code			= expinst exp : code
	where	
	   expinst (I i)		= PUSHINT i 
	   expinst (B b)		= PUSHBOOL b
	   expinst (V v)		= PUSH (d - s v)
	   expinst Nil			= PUSHNIL
	   expinst (Fname f)	= PUSHGLOBAL f

builtins :: Code
builtins = concat (map builtin ["cons", "head", "tail", "if", "null", "+", "-", "*", "=="])

builtin :: String -> Code
--builtin "not"	= [GLOBSTART "not", EVAL, NEG, UPDATE 1, RETURN]
builtin "cons"	= [GLOBSTART "cons" 2, CONS, UPDATE 1, RETURN]
builtin "head"	= [GLOBSTART "car" 1, EVAL, HEAD, EVAL, UPDATE 1, UNWIND]
builtin "tail"	= [GLOBSTART "cdr" 1, EVAL, TAIL, EVAL, UPDATE 1, UNWIND]
builtin "null"	= [GLOBSTART "null" 1, EVAL, PUSHNIL, EQU, UPDATE 1, UNWIND]
builtin "if"	= [	GLOBSTART "if" 3, 
					PUSH 0,
					EVAL,
					JFALSE "1",
					PUSH 1,
					JUMP "2",
					LABEL "1",
					PUSH 2,
					LABEL "2",
					EVAL,
					UPDATE 4,
					POP 3,
					UNWIND ]
builtin "+" = binarybuiltin "+"
builtin "-" = binarybuiltin "-"
builtin "*" = binarybuiltin "*"
builtin "/" = binarybuiltin "/"
builtin "==" = binarybuiltin "=="

binarybuiltin :: String -> Code
binarybuiltin op = [ GLOBSTART op 2,
					PUSH 1,
					EVAL,
					PUSH 1,
					EVAL,
					opcode op,
					UPDATE 3,
					POP 2,
					UNWIND ]
	where 
	   opcode "+" = ADD
	   opcode "-" = SUB
	   opcode "*" = MUL
	   opcode "/" = DIV
	   opcode "==" = EQU

-------------------------------------------------------------------------------------------------
--------------------------------------------- Interpreter ---------------------------------------

type Tag = Int

type Label = String

type Stack = [Tag]

data Node =	  NApp Tag Tag
			| NDef Label Int Code
			| NInt Int
			| NBool Bool
			| NNil
			| NCons Tag Tag
			deriving Show

type Heap = [(Tag, Node)]

type Dump = [(Code, Stack)]

type Globals = [(Tag, Label)]

type Output = [String]

type State = (Stack, Heap, Code, Dump, Globals, Output)

run :: Code -> Output
run code = reverse output
	where
		(main, func) = extract_main code
		(init_heap, globals) = find_globals func
		(_, _, _, _, _, output) = eval ([], init_heap, main, [], globals, [])

extract_main ((LABEL l):code) = if l == "MAIN" then func_code code else extract_main code
extract_main (c:code) = (m, c:cs)
	where (m, cs) = extract_main code

base_heap :: Heap
base_heap = [(2, NBool False), (1, NBool True), (0, NNil)]

find_globals :: Code -> (Heap, Globals)
find_globals [] = (base_heap, [])
find_globals ((GLOBSTART label nargs):cs) = ((tag, NDef label nargs cs'):h, (tag, label):g)
	where 
	   (cs', cs'') = func_code cs
	   (h, g) = find_globals cs''
	   tag = length h
find_globals (_:cs) = find_globals cs

func_code :: Code -> (Code, Code)
func_code [] = ([], [])
func_code cs@((GLOBSTART _ _):_) = ([], cs)
func_code (c:cs) = (c:cs', cs'')
	where 
	   (cs', cs'') = func_code cs

eval:: State -> State
eval (n:s, h, EVAL:c, d, g, o) = f top											------ EVAL
	where 
		top				= lookup_tag h n
		f (NApp t1 t2)	= eval ([n], h, [UNWIND], (c, s):d, g, o)
		f (NDef _ 0 c')	= eval (n:s, h'', c, d, g, o')
			where 
				([t], h', _, _, _, o') = eval ([n], h, c', [([],[])], g, o)
				h'' = update_heap h' n (lookup_tag h' t)
		f _				= eval (n:s, h, c, d, g, o)
eval (n:s, h, [UNWIND], d, g, o) = f top										------- UNWIND
	where 
		top				= lookup_tag h n
		(cs, s'):d'		= d
		f (NApp t1 _)	= eval (t1:n:s, h, [UNWIND], d, g, o)
		f (NDef _ k c)	= eval (if length s < k then (last s:s', h, cs, d', g, o) else (nks, h, c, d, g, o))
			where 
				(vs, s'')	= split s k
				vk			= vs!!(k - 1)
				nodes		= map (lookup_tag h) vs
				nks			= foldr (\ (NApp _ n) y -> n:y) (vk:s'') nodes
		f _				= eval (n:s', h, cs, d', g, o)
eval (s, h, [RETURN], (cs, s'):d, g, o) = eval (last s:s', h, cs, d, g, o)		------- RETURN
eval (s, h, JUMP label:cs, d, g, o) = eval (s, h, cs', d, g, o)					------- JUMP 
	where cs' = after label cs
eval (n:s, h, JFALSE label:cs, d, g, o) = eval state							------- JFALSE 
	where 
		NBool b = lookup_tag h n
		cs'		= after label cs
		state	| b = (s, h, cs, d, g, o)
				| otherwise = (s, h, cs', d, g, o)
eval (s, h, PUSH k:cs, d, g, o) = eval ((s!!k):s, h, cs, d, g, o)				------- PUSH 
eval (s, h, PUSHINT i:cs, d, g, o) = eval (t:s, (t, n):h, cs, d, g, o)			------- PUSHINT 
	where 
		t = length h
		n = NInt i
eval (s, h, PUSHBOOL b:cs, d, g, o) = eval (t:s, h, cs, d, g, o)				------- PUSHBOOL 
	where t = if b then 1 else 2
eval (s, h, PUSHNIL:cs, d, g, o) = eval (0:s, h, cs, d, g, o)					------- PUSHNIL
eval (s, h, PUSHGLOBAL f:cs, d, g, o) = eval (t:s, h, cs, d, g, o)				------- PUSHGLOBAL 
	where t = lookup_global f g
eval (s, h, POP k:cs, d, g, o) = eval (s', h, cs, d, g, o)						------- POP 
	where (_, s') = split s k
eval (s@(t:s'), h, UPDATE k:cs, d, g, o) = eval (s', h', cs, d, g, o)			------- UPDATE 
	where
		node	= lookup_tag h t
		nk		= s!!k
		h'		= update_heap h nk node
eval (t:s, h, HEAD:cs, d, g, o) = eval (t1:s, h, cs, d, g, o)					------- HEAD
	where NCons t1 _ = lookup_tag h t
eval (t:s, h, TAIL:cs, d, g, o) = eval (t2:s, h, cs, d, g, o)					------- TAIL
	where NCons _ t2 = lookup_tag h t
eval (t1:t2:s, h, ADD:cs, d, g, o) = eval (t:s, (t, node):h, cs, d, g, o)		------- ADD
	where (t, node) = binary_op ADD t1 t2 h
eval (t1:t2:s, h, SUB:cs, d, g, o) = eval (t:s, (t, node):h, cs, d, g, o)		------- SUB
	where (t, node) = binary_op SUB t1 t2 h
eval (t1:t2:s, h, MUL:cs, d, g, o) = eval (t:s, (t, node):h, cs, d, g, o)		------- MUL
	where (t, node) = binary_op MUL t1 t2 h
eval (t1:t2:s, h, DIV:cs, d, g, o) = eval (t:s, (t, node):h, cs, d, g, o)		------- DIV
	where (t, node) = binary_op DIV t1 t2 h
eval (t1:t2:s, h, EQU:cs, d, g, o) = eval (t:s, h, cs, d, g, o)					------- EQU
	where (t, _) = binary_op EQU t1 t2 h
eval (t1:t2:s, h, MKAP:cs, d, g, o) = eval (t:s, (t, NApp t1 t2):h, cs, d, g, o)	------- MKAP
	where t = length h
eval (t1:t2:s, h, CONS:cs, d, g, o) = eval (t:s, (t, NCons t1 t2):h, cs, d, g, o)	------- CONS
	where t = length h
eval (s, h, LABEL _:cs, d, g, o) = eval (s, h, cs, d, g, o)						------- LABEL 
eval (t:s, h, PRINT:cs, d, g, o) = f top										------- PRINT
	where 
	   top = lookup_tag h t
	   f (NInt i) = eval (s, h, cs, d, g, (show i):o)
	   f (NBool b) = eval (s, h, cs, d, g, (show b):o)
	   f (NCons t1 t2) = eval (t1:t2:s, h, EVAL:PRINT:EVAL:PRINT:cs, d, g, o)
	   f (NApp t1 t2) = eval (t:s, h, EVAL:PRINT:cs, d, g, o)
	   f _ = eval (s, h, cs, d, g, o)
eval (s, h, STOP:cs, d, g, o) = (s, h, [], d, g, o)								------- STOP
eval (s, h, [], d, g, o) = (s, h, [], d, g, o)


after :: Label -> Code -> Code													
after l (LABEL x:cs) = if x == l then cs else after l cs
after l (_:cs) = after l cs

split :: [a] -> Int -> ([a], [a])
split xs 0 = ([], xs)
split (x:xs) n = (x:xs', xs'')
	where (xs', xs'') = split xs (n - 1)

lookup_global :: Label -> Globals -> Tag
--lookup_global label [] = -1
lookup_global label ((tag, l):gs)	| label == l = tag
									| otherwise = lookup_global label gs

lookup_tag :: Heap -> Tag -> Node
--lookup_tag ((t, n):h) k | t == k = n
--						| otherwise = lookup_tag h k
lookup_tag h t = snd (h!!(length h - t - 1))

update_heap :: Heap -> Tag -> Node -> Heap
update_heap ((t, n):h) k node	| k == t = (t, node):h
								| otherwise = (t, n):update_heap h k node

binary_op :: Instn -> Tag -> Tag -> Heap -> (Tag, Node)
binary_op EQU t1 t2 h = (t, NBool b)
	where
		t = if b then 1 else 2
		b = is_equal (lookup_tag h t1) (lookup_tag h t2)
		is_equal (NInt a) (NInt b) = a == b
		is_equal (NBool a) (NBool b) = a == b
		is_equal NNil NNil = True
		is_equal _ _ = False
binary_op op_code t1 t2 h = (t, node)
	where
		t = length h
		op = code_fun op_code
		NInt n1 = lookup_tag h t1
		NInt n2 = lookup_tag h t2
		node = NInt (n1 `op` n2)
		code_fun ADD = (+)
		code_fun SUB = (-)
		code_fun MUL = (*)
		code_fun DIV = div

main = do 
	input <- readFile "pfile"
	let
		code = (gencpgm . parse) input
		output = run code
	putStr (concat output ++ "\n")


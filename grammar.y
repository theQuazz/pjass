// Jass2 parser for bison/yacc
// by Rudi Cilibrasi
// Sun Jun  8 00:51:53 CEST 2003
// thanks to Jeff Pang for the handy documentation that this was based
// on at http://jass.sourceforge.net
%{

#include <stdio.h>
#include <string.h>
#include "misc.h"

#define YYMAXDEPTH 25000

int yyerrorline (int errorlevel, int line, char *s)
{
  if (showerrorlevel[errorlevel]) {
    haderrors++;
    printf ("%s:%d: %s\n", curfile, line, s);
    return 0;
  }
  else
    ignorederrors++;
}

int yyerrorex (int errorlevel, char *s)
{
  if (showerrorlevel[errorlevel]) {
    haderrors++;
    printf ("%s:%d: %s\n", curfile, lineno, s);
    return 0;
  }
  else
    ignorederrors++;
}

int yyerror (char *s)  /* Called by yyparse on error */
{
  yyerrorex(0, s);
}

int main(int argc, char **argv)
{
  init(argc, argv);
  if (1)  {
		doparse(argc, argv);
  }
  else {
    for (;;) {
      int result = yylex();
      if (result == 0) break;
      printf("Got result %d, %s\n", result, yytext);
    }
  }
  if (!haderrors && didparse) {
		printf("Parse successful: %8d lines: %s\n", totlines, "<total>");
    if (ignorederrors)
	printf("%d errors ignored", ignorederrors);

    return 0;
  }
  else {
		if (haderrors)
			printf("Parse failed: %d error%s total\n", haderrors, haderrors == 1 ? "" : "s");
		else
			printf("Parse failed\n");
		if (ignorederrors)
		  printf("%d errors ignored", ignorederrors);
    return 1;
	}
}

#define YYSTYPE union node

%}

%token IF
%token THEN
%token TYPE
%token EXTENDS
%token HANDLE
%token NEWLINE
%token GLOBALS
%token ENDGLOBALS
%token CONSTANT
%token NATIVE
%token TAKES
%token RETURNS
%token FUNCTION
%token ENDFUNCTION
%token LOCAL
%token ARRAY
%token SET
%token CALL
%token ELSE
%token ELSEIF
%token ENDIF
%token LOOP
%token EXITWHEN
%token RETURN
%token DEBUG
%token ENDLOOP
%token NOT
%token TNULL
%token TTRUE
%token TFALSE
%token CODE
%token STRING
%token INTEGER
%token REAL
%token BOOLEAN
%token NOTHING
%token ID
%token COMMENT
%token COMMA
%token AND
%token OR
%token EQUALS
%token TIMES
%token DIV
%token PLUS
%token MINUS
%token LPAREN
%token RPAREN
%token LBRACKET
%token RBRACKET
%token LESS
%token GREATER
%token LEQ
%token GEQ
%token EQCOMP
%token NEQ
%token STRINGLIT
%token INTLIT
%token REALLIT
%token UNITTYPEINT

%right EQUALS
%left AND OR
%left LESS GREATER EQCOMP NEQ LEQ GEQ
%left NOT
%left MINUS PLUS
%left TIMES DIV

%%

program: topscopes globdefs topscopes funcdefns
;

topscopes: topscope
       | topscopes topscope
;

topscope: typedefs  
       | funcdecls
;

funcdefns: /* empty */
       | funcdefns funcdefn
;

globdefs: /* empty */
         | GLOBALS NEWLINE vardecls ENDGLOBALS endglobalsmarker
         | GLOBALS vardecls ENDGLOBALS endglobalsmarker {yyerrorline(0, lineno - 1, "Missing linebreak before global declaration");}
;

endglobalsmarker: /* empty */  {afterendglobals = 1}
;

vardecls: /* empty */
         | vd vardecls
;

vd:      NEWLINE
       | vardecl
;

funcdecls: /* empty */
         | fd funcdecls
;

fd:      NEWLINE
       | funcdecl
;

typedefs:  /* empty */
         | td typedefs
;

td:      NEWLINE
       | typedef
;

// Returns a typenode
expr: intexpr      { $$.ty = gInteger; }
      | realexpr   { $$.ty = gReal; }
      | stringexpr { $$.ty = gString; }
      | boolexpr   { $$.ty = gBoolean; }
      | FUNCTION rid { struct funcdecl *fd = lookup(&functions, $2.str);
                       if (fd == NULL) {
                           char ebuf[1024];
                           sprintf(ebuf, "Undefined function %s", $2.str);
                           yyerrorex(3, ebuf);
                           $$.ty = gCode;
                       } else {
                           if (fd->p->head != NULL) {
                               char ebuf[1024];
                               sprintf(ebuf, "Function %s must not take any arguments when used as code", $2.str);
                               yyerrorex(3, ebuf);
                           }
                           if (fd->ret == gBoolean)
                           	$$.ty = gCodeReturnsBoolean;
                           else
                              $$.ty = gCodeReturnsNoBoolean;
                       }
                     }
      | TNULL { $$.ty = gNull; }
      | expr LEQ expr { checkcomparison($1.ty, $3.ty); $$.ty = gBoolean; }
      | expr GEQ expr { checkcomparison($1.ty, $3.ty); $$.ty = gBoolean; }
      | expr LESS expr { checkcomparison($1.ty, $3.ty); $$.ty = gBoolean; }
      | expr GREATER expr { checkcomparison($1.ty, $3.ty); $$.ty = gBoolean; }
      | expr EQCOMP expr { checkeqtest($1.ty, $3.ty); $$.ty = gBoolean; }
      | expr NEQ expr { checkeqtest($1.ty, $3.ty); $$.ty = gBoolean; }
      | expr AND expr { canconvert($1.ty, gBoolean, 0); canconvert($3.ty, gBoolean, 0); $$.ty = gBoolean; }
      | expr OR expr { canconvert($1.ty, gBoolean, 0); canconvert($3.ty, gBoolean, 0); $$.ty = gBoolean; }
      | NOT expr { canconvert($2.ty, gBoolean, 0); $$.ty = gBoolean; }
      | expr TIMES expr { $$.ty = binop($1.ty, $3.ty); }
      | expr DIV expr { $$.ty = binop($1.ty, $3.ty); }
      | expr MINUS expr { $$.ty = binop($1.ty, $3.ty); }
      | expr PLUS expr { 
                         if ($1.ty == gString && $3.ty == gString)
                           $$.ty = gString;
                         else
                           $$.ty = binop($1.ty, $3.ty); }
      | MINUS expr { isnumeric($2.ty); $$.ty = $2.ty; }
      | LPAREN expr RPAREN { $$.ty = $2.ty; }
      | funccall { $$.ty = $1.ty }
      | rid LBRACKET expr RBRACKET {
          const struct typeandname *tan = getVariable($1.str);
          if (tan->ty != gAny) {
            if (!tan->isarray) {
              char ebuf[1024];
              sprintf(ebuf, "%s not an array", $1.str);
              yyerrorex(3, ebuf);
            }
            else {
              canconvert($3.ty, gInteger, 0);
            }
          }
          $$.ty = tan->ty;
       }
      | rid {
          const struct typeandname *tan = getVariable($1.str);
          if (tan->lineno == lineno && tan->fn == fno) {
            char ebuf[1024];
            sprintf(ebuf, "Use of variable %s before its declaration", $1.str);
            yyerrorex(3, ebuf);
          } else if (islinebreak && tan->lineno == lineno - 1 && tan->fn == fno) {
            char ebuf[1024];
            sprintf(ebuf, "Use of variable %s before its declaration", $1.str);
            yyerrorline(3, lineno - 1, ebuf);
          } else if (tan->isarray) {
            char ebuf[1024];
            sprintf(ebuf, "Index missing for array variable %s", $1.str);
            yyerrorex(3, ebuf);
          }
          $$.ty = tan->ty;
       }
      | expr EQUALS expr {yyerrorex(0, "Single = in expression, should probably be =="); checkeqtest($1.ty, $3.ty); $$.ty = gBoolean;}
      | LPAREN expr {yyerrorex(0, "Mssing ')'"); $$.ty = $2.ty;}
      
      // incomplete expressions 
      | expr LEQ { checkcomparisonsimple($1.ty); yyerrorex(3, "Missing expression for comparison"); $$.ty = gBoolean; }
      | expr GEQ { checkcomparisonsimple($1.ty); yyerrorex(3, "Missing expression for comparison"); $$.ty = gBoolean; }
      | expr LESS { checkcomparisonsimple($1.ty); yyerrorex(3, "Missing expression for comparison"); $$.ty = gBoolean; }
      | expr GREATER { checkcomparisonsimple($1.ty); yyerrorex(3, "Missing expression for comparison"); $$.ty = gBoolean; }
      | expr EQCOMP { yyerrorex(3, "Missing expression for comparison"); $$.ty = gBoolean; }
      | expr NEQ { yyerrorex(3, "Missing expression for comparison"); $$.ty = gBoolean; }
      | expr AND { canconvert($1.ty, gBoolean, 0); yyerrorex(3, "Missing expression for logical and"); $$.ty = gBoolean; }
      | expr OR { canconvert($1.ty, gBoolean, 0); yyerrorex(3, "Missing expression for logical or"); $$.ty = gBoolean; }
      | NOT { yyerrorex(3, "Missing expression for logical negation"); $$.ty = gBoolean; }
;

funccall: rid LPAREN exprlistcompl RPAREN {
          struct funcdecl *fd = lookup(&functions, $1.str);
          if (fd == NULL) {
            char ebuf[1024];
            sprintf(ebuf, "Undeclared function %s", $1.str);
            yyerrorex(3, ebuf);
            $$.ty = gNull;
          } else {
            if (inconstant && !(fd->isconst)) {
              char ebuf[1024];
              sprintf(ebuf, "Call to non-constant function %s in constant function", $1.str);
              yyerrorex(3, ebuf);
            }
            if (fd == fCurrent && fCurrent)
          		yyerrorex(3, "Recursive function calls are not permitted in local declarations");
            checkParameters(fd->p, $3.pl, (fd==fFilter || fd==fCondition));
            $$.ty = fd->ret;
          }
       }
       |  rid LPAREN exprlistcompl NEWLINE {
          yyerrorex(0, "Missing ')'");
          struct funcdecl *fd = lookup(&functions, $1.str);
          if (fd == NULL) {
            char ebuf[1024];
            sprintf(ebuf, "Undeclared function %s", $1.str);
            yyerrorex(3, ebuf);
            $$.ty = gNull;
          } else if (inconstant && !(fd->isconst)) {
            char ebuf[1024];
            sprintf(ebuf, "Call to non-constant function %s in constant function", $1.str);
            yyerrorex(3, ebuf);
            $$.ty = gNull;
          } else {
          	if (fd == fCurrent && fCurrent)
          		yyerrorex(3, "Recursive function calls are not permitted in local declarations");
            checkParameters(fd->p, $3.pl, (fd==fFilter || fd==fCondition));
            $$.ty = fd->ret;
          }
       }
;

exprlistcompl: /* empty */ { $$.pl = newparamlist(); }
       | exprlist { $$.pl = $1.pl; }
;

exprlist: expr         { $$.pl = newparamlist(); addParam($$.pl, newtypeandname($1.ty, "")); }
       |  expr COMMA exprlist { $$.pl = $3.pl; addParam($$.pl, newtypeandname($1.ty, "")); }
;


stringexpr: STRINGLIT { $$.ty = gString; }
;

realexpr: REALLIT { $$.ty = gReal; }
;

boolexpr: boollit { $$.ty = gBoolean; }
;

boollit: TTRUE
       | TFALSE
;

intexpr:   INTLIT { $$.ty = gInteger; }
         | UNITTYPEINT { $$.ty = gInteger; }
;


funcdecl: nativefuncdecl { $$.fd = $1.fd; }
         | CONSTANT nativefuncdecl { $$.fd = $2.fd; }
         | funcdefncore { $$.fd = $1.fd; }
;

nativefuncdecl: NATIVE rid TAKES optparam_list RETURNS opttype
{
  if (lookup(&locals, $2.str) || lookup(&params, $2.str) || lookup(&globals, $2.str)) {
    char buf[1024];
    sprintf(buf, "%s already defined as variable", $2.str);
    yyerrorex(3, buf);
  } else if (lookup(&types, $2.str)) {
    char buf[1024];
    sprintf(buf, "%s already defined as type", $2.str);
    yyerrorex(3, buf);
  }
  $$.fd = newfuncdecl(); 
  $$.fd->name = strdup($2.str);
  $$.fd->p = $4.pl;
  $$.fd->ret = $6.ty;
  //printf("***** %s = %s\n", $2.str, $$.fd->ret->typename);
  $$.fd->isconst = isconstant;
  if (strcmp($$.fd->name, "Filter") == 0)
    fFilter = $$.fd;
  if (strcmp($$.fd->name, "Condition") == 0)
    fCondition = $$.fd;
  put(&functions, $$.fd->name, $$.fd);
  //showfuncdecl($$.fd);
}
;

funcdefn: NEWLINE
       | funcdefncore
       | statement { yyerrorex(0, "Statement outside of function"); }
;

funcdefncore: funcbegin localblock codeblock funcend { if(retval != gNothing) { if ($3.ty == gAny || $3.ty == gNone) yyerrorline(1, lineno - 1, "Missing return"); else if (returnbug) canconvertreturn($3.ty, retval, -1); } }
       | funcbegin localblock codeblock {yyerrorex(0, "Missing endfunction"); clear(&params); clear(&locals); curtab = &globals;}
;

funcend: ENDFUNCTION { clear(&params); clear(&locals); curtab = &globals; inblock = 0; inconstant = 0; }
;

returnorreturns: RETURNS
               | RETURN {yyerrorex(3,"Expected \"returns\" instead of \"return\"");}
;

funcbegin: FUNCTION rid TAKES optparam_list returnorreturns opttype {
  if (lookup(&locals, $2.str) || lookup(&params, $2.str) || lookup(&globals, $2.str)) {
    char buf[1024];
    sprintf(buf, "%s already defined as variable", $2.str);
    yyerrorex(3, buf);
  } else if (lookup(&types, $2.str)) {
    char buf[1024];
    sprintf(buf, "%s already defined as type", $2.str);
    yyerrorex(3, buf);
  }
  inconstant = 0;
  curtab = &locals;
  $$.fd = newfuncdecl(); 
  $$.fd->name = strdup($2.str);
  $$.fd->p = $4.pl;
  $$.fd->ret = $6.ty;
  $$.fd->isconst = 0;
  put(&functions, $$.fd->name, $$.fd);
  fCurrent = lookup(&functions, $2.str);
  struct typeandname *tan = $4.pl->head;
  for (;tan; tan=tan->next) {
    tan->lineno = lineno;
    tan->fn = fno;
    put(&params, strdup(tan->name), newtypeandname(tan->ty, tan->name));
    if (lookup(&functions, tan->name)) {
      char buf[1024];
      sprintf(buf, "%s already defined as function", tan->name);
      yyerrorex(3, buf);
    } else if (lookup(&types, tan->name)) {
      char buf[1024];
      sprintf(buf, "%s already defined as type", tan->name);
      yyerrorex(3, buf);
    }
  }
  retval = $$.fd->ret;
  inblock = 1;
  inloop = 0;
  //showfuncdecl($$.fd);
}
       | CONSTANT FUNCTION rid TAKES optparam_list returnorreturns opttype {
  if (lookup(&locals, $3.str) || lookup(&params, $3.str) || lookup(&globals, $3.str)) {
    char buf[1024];
    sprintf(buf, "%s already defined as variable", $3.str);
    yyerrorex(3, buf);
  } else if (lookup(&types, $3.str)) {
    char buf[1024];
    sprintf(buf, "%s already defined as type", $3.str);
    yyerrorex(3, buf);
  }
  inconstant = 1;
  curtab = &locals;
  $$.fd = newfuncdecl(); 
  $$.fd->name = strdup($3.str);
  $$.fd->p = $5.pl;
  $$.fd->ret = $7.ty;
  $$.fd->isconst = 1;
  put(&functions, $$.fd->name, $$.fd);
  struct typeandname *tan = $5.pl->head;
  for (;tan; tan=tan->next) {
    tan->lineno = lineno;
    tan->fn = fno;
    put(&params, strdup(tan->name), newtypeandname(tan->ty, tan->name));
    if (lookup(&functions, tan->name)) {
      char buf[1024];
      sprintf(buf, "%s already defined as function", tan->name);
      yyerrorex(3, buf);
    } else if (lookup(&types, tan->name)) {
      char buf[1024];
      sprintf(buf, "%s already defined as type", tan->name);
      yyerrorex(3, buf);
    }
  }
  retval = $$.fd->ret;
  inblock = 1;
  inloop = 0;
  //showfuncdecl($$.fd);
}
;

codeblock: /* empty */ {$$.ty = gAny;}
       | statement codeblock { if($2.ty == gAny) $$.ty = $1.ty; else $$.ty = $2.ty;}
;

statement:  NEWLINE {$$.ty = gAny;}
       | CALL funccall NEWLINE{ $$.ty = gNone;}
       | IF expr THEN NEWLINE codeblock elsifseq elseseq ENDIF NEWLINE { canconvert($2.ty, gBoolean, -1); $$.ty = combinetype($6.ty!=gAny?combinetype($5.ty, $6.ty):$5.ty, $7.ty);}
       | SET rid EQUALS expr NEWLINE { if (getVariable($2.str)->isarray) {
                                         char ebuf[1024];
                                         sprintf(ebuf, "Index missing for array variable %s", $2.str);
                                         yyerrorline(3, lineno - 1,  ebuf);
                                       }
                                       canconvert($4.ty, getVariable($2.str)->ty, -1);
                                       $$.ty = gNone;
                                       if (getVariable($2.str)->isconst) {
                                         char ebuf[1024];
                                         sprintf(ebuf, "Cannot assign to constant %s", $2.str);
                                         yyerrorline(3, lineno - 1, ebuf);
                                       }
                                       if (inconstant)
                                         validateGlobalAssignment($2.str);
				    }
       | SET rid LBRACKET expr RBRACKET EQUALS expr NEWLINE{ 
           const struct typeandname *tan = getVariable($2.str);
           if (tan->ty != gAny) {
             canconvert($4.ty, gInteger, -1); $$.ty = gNone;
             if (!tan->isarray) {
               char ebuf[1024];
               sprintf(ebuf, "%s is not an array", $2.str);
               yyerrorline(3, lineno - 1, ebuf);
             }
             canconvert($7.ty, tan->ty, -1);
             if (inconstant)
               validateGlobalAssignment($2.str);
             }
           }
       | loopstart NEWLINE codeblock loopend NEWLINE {$$.ty = $3.ty;}
       | loopstart NEWLINE codeblock {$$.ty = $3.ty; yyerrorex(0, "Missing endloop");}
       | EXITWHEN expr NEWLINE { canconvert($2.ty, gBoolean, -1); if (!inloop) yyerrorline(0, lineno - 1, "Exitwhen outside of loop"); $$.ty = gNone;}
       | RETURN expr NEWLINE { $$.ty = $2.ty; if(retval == gNothing) yyerrorline(1, lineno - 1, "Cannot return value from function that returns nothing"); else if (!returnbug) canconvertreturn($2.ty, retval, 0); }
       | RETURN NEWLINE { if (retval != gNothing) yyerrorline(1, lineno - 1, "Return nothing in function that should return value"); $$.ty = gNone;}
       | DEBUG statement {$$.ty = gNone;}
       | IF expr THEN NEWLINE codeblock elsifseq elseseq {canconvert($2.ty, gBoolean, 0); $$.ty = combinetype($6.ty!=gAny?combinetype($5.ty, $6.ty):$5.ty, $7.ty); yyerrorex(0, "Missing endif");}
       | IF expr NEWLINE{canconvert($2.ty, gBoolean, -1); $$.ty = gAny; yyerrorex(0, "Missing then or non valid expression");}
       | SET funccall NEWLINE{$$.ty = gNone; yyerrorline(0, lineno - 1, "Call expected instead of set");}
       | lvardecl {yyerrorex(0, "Local declaration after first statement");}
       | error {$$.ty = gNone; }
;

loopstart: LOOP {inloop++;}
;

loopend: ENDLOOP {inloop--;}
;

elseseq: /* empty */ {$$.ty = gNone;}
        | ELSE NEWLINE codeblock {$$.ty = $3.ty;}
;

elsifseq: /* empty */ {$$.ty = gAny;}
        | ELSEIF expr THEN NEWLINE codeblock elsifseq { canconvert($2.ty, gBoolean, -1); $$.ty = $6.ty!=gAny?combinetype($5.ty, $6.ty):$5.ty;}
;

optparam_list: param_list { $$.pl = $1.pl; }
               | NOTHING { $$.pl = newparamlist(); }
;

opttype: NOTHING { $$.ty = gNothing; }
         | type { $$.ty = $1.ty; }
;

param_list: typeandname { $$.pl = newparamlist(); addParam($$.pl, $1.tan); }
          | typeandname COMMA param_list { addParam($3.pl, $1.tan); $$.pl = $3.pl; }
;

rid: ID
{ $$.str = strdup(yytext); }
;

vartypedecl: type rid {
  if (lookup(&functions, $2.str)) {
    char buf[1024];
    sprintf(buf, "Symbol %s already defined as function", $2.str);
    yyerrorex(3, buf);
  } else if (lookup(&types, $2.str)) {
    char buf[1024];
    sprintf(buf, "Symbol %s already defined as type", $2.str);
    yyerrorex(3, buf);
  }
  struct typeandname *tan = newtypeandname($1.ty, $2.str);
  $$.str = $2.str;
  struct typeandname *existing = lookup(&locals, $2.str);
  if (!existing) {
    existing = lookup(&params, $2.str);
    if (!existing)
      existing = lookup(&globals, $2.str);
  }
  if (existing) {
    tan->lineno = existing->lineno;
    tan->fn = existing->fn;
  } else {
    tan->lineno = lineno;
    tan->fn = fno;
  }
  put(curtab, $2.str, tan);  }
       | CONSTANT type rid {
  if (afterendglobals) {
    yyerrorex(3, "Local constants are not allowed");
  }
  if (lookup(&functions, $3.str)) {
    char buf[1024];
    sprintf(buf, "Symbol %s already defined as function", $3.str);
    yyerrorex(3, buf);
  } else if (lookup(&types, $3.str)) {
    char buf[1024];
    sprintf(buf, "Symbol %s already defined as type", $3.str);
    yyerrorex(3, buf);
  }
  struct typeandname *tan = newtypeandname($2.ty, $3.str);
  $$.str = $3.str;
  tan->isconst = 1;
  struct typeandname *existing = lookup(&locals, $3.str);
  if (!existing) {
    existing = lookup(&params, $3.str);
    if (!existing)
      existing = lookup(&globals, $3.str);
  }
  if (existing) {
    tan->lineno = existing->lineno;
    tan->fn = existing->fn;
  } else {
    tan->lineno = lineno;
    tan->fn = fno;
  }
  put(curtab, $3.str, tan); }
       | type ARRAY rid {
  if (lookup(&functions, $3.str)) {
    char buf[1024];
    sprintf(buf, "Symbol %s already defined as function", $3.str);
    yyerrorex(3, buf);
  } else if (lookup(&types, $3.str)) {
    char buf[1024];
    sprintf(buf, "Symbol %s already defined as type", $3.str);
    yyerrorex(3, buf);
  }
  if (getPrimitiveAncestor($1.ty) == gCode)
    yyerrorex(3, "Code arrays are not allowed");
  struct typeandname *tan = newtypeandname($1.ty, $3.str);
  $$.str = $3.str;
  tan->isarray = 1;
  struct typeandname *existing = lookup(&locals, $3.str);
  if (!existing) {
    char buf[1024];
    existing = lookup(&params, $3.str);
    if (afterendglobals && existing) {
    	sprintf(buf, "Symbol %s already defined as function parameter", $3.str);
    	yyerrorex(3, buf);
    }
    if (!existing) {
      existing = lookup(&globals, $3.str);
      if (afterendglobals && existing) {
      	sprintf(buf, "Symbol %s already defined as global variable", $3.str);
      	yyerrorex(3, buf);
      }
    }
  }
  if (existing) {
    tan->lineno = existing->lineno;
    tan->fn = existing->fn;
  } else {
    tan->lineno = lineno;
    tan->fn = fno;
  }
  put(curtab, $3.str, tan); }
  
 // using "type" as variable name 
      | type TYPE {
  yyerrorex(3, "Invalid variable name \"type\"");
  struct typeandname *tan = newtypeandname($1.ty, "type");
  $$.str = "type";
  struct typeandname *existing = lookup(&locals, "type");
  if (!existing) {
    existing = lookup(&params, "type");
    if (!existing)
      existing = lookup(&globals, "type");
  }
  if (existing) {
    tan->lineno = existing->lineno;
    tan->fn = existing->fn;
  } else {
    tan->lineno = lineno;
    tan->fn = fno;
  }
  put(curtab, "type", tan);  }
       | CONSTANT type TYPE {
  if (afterendglobals) {
    yyerrorex(3, "Local constants are not allowed");
  }
  yyerrorex(3, "Invalid variable name \"type\"");
  struct typeandname *tan = newtypeandname($2.ty, "type");
  $$.str = "type";
  tan->isconst = 1;
  struct typeandname *existing = lookup(&locals, "type");
  if (!existing) {
    existing = lookup(&params, "type");
    if (!existing)
      existing = lookup(&globals, "type");
  }
  if (existing) {
    tan->lineno = existing->lineno;
    tan->fn = existing->fn;
  } else {
    tan->lineno = lineno;
    tan->fn = fno;
  }
  put(curtab, "type", tan); }
       | type ARRAY TYPE {
  yyerrorex(3, "Invalid variable name \"type\"");
  struct typeandname *tan = newtypeandname($1.ty, "type");
  $$.str = "type";
  tan->isarray = 1;
  struct typeandname *existing = lookup(&locals, "type");
  if (!existing) {
    existing = lookup(&params, "type");
    if (!existing)
      existing = lookup(&globals, "type");
  }
  if (existing) {
    tan->lineno = existing->lineno;
    tan->fn = existing->fn;
  } else {
    tan->lineno = lineno;
    tan->fn = fno;
  }
  put(curtab, "type", tan); }
;

localblock: endlocalsmarker
        | lvardecl localblock
        | NEWLINE localblock
;

endlocalsmarker: /* empty */ { fCurrent = 0; }
;

lvardecl: LOCAL vardecl { }
        | CONSTANT LOCAL vardecl { yyerrorex(3, "Local variables can not be declared constant"); }
        | typedef { yyerrorex(3,"Types can not be extended inside functions"); }
;

vardecl: vartypedecl NEWLINE {
             const struct typeandname *tan = getVariable($1.str);
             if (tan->isconst) {
               yyerrorline(3, lineno - 1, "Constants must be initialized");
             }
             $$.ty = gNothing;
           }
        |  vartypedecl EQUALS expr NEWLINE {
             const struct typeandname *tan = getVariable($1.str);
             if (tan->isarray) {
               yyerrorex(3, "Arrays cannot be directly initialized");
             }
             canconvert($3.ty, tan->ty, -1);
             $$.ty = gNothing;
           }
        | error
;

typedef: TYPE rid EXTENDS type {
  if (lookup(&types, $2.str)) {
     char buf[1024];
     sprintf(buf, "Multiply defined type %s", $2.str);
     yyerrorex(3, buf);
  } else if (lookup(&functions, $2.str)) {
    char buf[1024];
    sprintf(buf, "%s already defined as function", $2.str);
    yyerrorex(3, buf);
  }
  else
    put(&types, $2.str, newtypenode($2.str, $4.ty));
}
;

typeandname: type rid { $$.tan = newtypeandname($1.ty, $2.str); }
;
  
type: primtype { $$.ty = $1.ty; }
  | rid {
   if (lookup(&types, $1.str) == NULL) {
     char buf[1024];
     sprintf(buf, "Undefined type %s", $1.str);
     yyerrorex(3, buf);
     $$.ty = gNull;
   }
   else
     $$.ty = lookup(&types, $1.str);
}
;

primtype: HANDLE  { $$.ty = lookup(&types, yytext); }
 | INTEGER        { $$.ty = lookup(&types, yytext); }
 | REAL           { $$.ty = lookup(&types, yytext); }
 | BOOLEAN        { $$.ty = lookup(&types, yytext); }
 | STRING         { $$.ty = lookup(&types, yytext); }
 | CODE           { $$.ty = lookup(&types, yytext); }
;


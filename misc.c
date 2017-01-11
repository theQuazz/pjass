// Jass2 parser for bison/yacc
// by Rudi Cilibrasi
// Sun Jun  8 00:51:53 CEST 2003
// thanks to Jeff Pang for the handy documentation that this was based
// on at http://jass.sourceforge.net
// Released under the BSD license
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <malloc.h>
#include "grammar.tab.h"
#include "misc.h"

#define VERSIONSTR "0.91"

int lineno;
int haderrors;
int totlines;
int didparse;

int hashfunc(const char *name);
struct hashtable functions, globals, locals, params, types;
struct hashtable *curtab;
struct typenode *retval;
char *curfile;
struct typenode *gInteger, *gReal, *gBoolean, *gString, *gCode, *gHandle, *gNothing, *gNull;

void addPrimitiveType(const char *name, struct typenode **toSave)
{
  put(&types, name, *toSave = newtypenode(name, NULL));
}

void init(int argc, char **argv)
{
  addPrimitiveType("handle", &gHandle);
  addPrimitiveType("integer", &gInteger);
  addPrimitiveType("real", &gReal);
  addPrimitiveType("boolean", &gBoolean);
  addPrimitiveType("string", &gString);
  addPrimitiveType("code", &gCode);
  gNothing = newtypenode("nothing", NULL);
  gNull = newtypenode("null", NULL);
  curtab = &globals;
  if (lookup(&functions, "ConvertRace") != NULL) {
     printf("Major error!!\n");
     exit(0);
  }
}

struct typenode *getFunctionType(const char *funcname)
{
  char ebuf[1024];
  struct funcdecl *result;
  result = lookup(&functions, funcname);
  if (result) return result->ret;
  sprintf(ebuf, "Undeclared function: %s\n", funcname);
  yyerror(ebuf);
}

const struct typeandname *getVariable(const char *varname)
{
  char ebuf[1024];
  struct typeandname *result;
  result = lookup(&locals, varname);
  if (result) return result;
  result = lookup(&params, varname);
  if (result) return result;
  result = lookup(&globals, varname);
  if (result) return result;
  sprintf(ebuf, "Undeclared variable: %s\n", varname);
  yyerror(ebuf);
  // Assume it's an int
  put(curtab, varname, newtypeandname(gInteger, varname));
  return getVariable(varname);
}

struct typeandname *newtypeandname(const struct typenode *ty, const char *name)
{
  struct typeandname *tan = calloc(sizeof(struct typeandname), 1);
  tan->ty = ty;
  tan->name = strdup(name);
  tan->next = NULL;
  return tan;
}

struct typenode *newtypenode(const char *typename, const struct typenode *superclass)
{
  struct typenode *result;
  result = calloc(sizeof(struct typenode), 1);
  result->typename = strdup(typename);
  result->superclass = superclass;
  return result;
}

struct paramlist *newparamlist()
{
  struct paramlist *tl = calloc(sizeof(struct paramlist), 1);
  tl->head = NULL;
  tl->tail = &tl->head;
  return tl;
}

void addParam(struct paramlist *pl, struct typeandname *tan)
{
  tan->next = *(pl->tail);
  *(pl->tail) = tan;
}

struct funcdecl *newfuncdecl()
{
  struct funcdecl *fd = calloc(sizeof(struct funcdecl), 1);
  fd->name = NULL;
  fd->p = NULL;
  fd->ret = NULL;
  return fd;
}

const struct typenode *getPrimitiveAncestor(const struct typenode *cur)
{
  while (cur->superclass)
    cur = cur->superclass;
  return cur;
}

int isDerivedFrom(const struct typenode *cur, const struct typenode *base)
{
  do {
    if (cur == base) return 1;
    cur = cur->superclass;
  } while (cur);
  return 0;
}

void showtypenode(const struct typenode *td)
{
  const char *tp = NULL;
  const char *tn = "";
  char *extends = "";
  char ebuf[1024];
  assert(td);
  assert(td->typename);
  /*
  if (td->superclass) {
    sprintf(ebuf, " extends %s", td->superclass->typename);
    extends = ebuf;
  }
  */
  printf("%s%s", td->typename, extends);
}

void showfuncdecl(struct funcdecl *fd)
{
  struct typeandname *tan;
  printf("%s takes ", fd->name);
  if (fd->p->head == NULL)
    printf("nothing ");
  for (tan = fd->p->head; tan; tan = tan->next) {
    showtypenode(tan->ty);
    printf(" %s", tan->name);
    if (tan->next)
      printf(",");
    printf(" ");
  }
  printf("returns ");
  showtypenode(fd->ret);
  printf("\n");
}


int hashfunc(const char *name)
{
  int h = 0;
  const unsigned char *s;
  for (s = name; *s; ++s)
    h = ((811 * h + (*s)) % 19205861);
  return ((h % BUCKETS) + BUCKETS) % BUCKETS;
}

void *lookup(struct hashtable *h, const char *name)
{
  struct hashnode *hn;
  int hf = hashfunc(name);
  hn = h->h[hf];
  while (hn) {
    if (strcmp(hn->name, name) == 0)
      return hn->val;
    hn = hn->next;
  }
  return NULL;
}

void put(struct hashtable *h, const char *name, void *val)
{
  struct hashnode *hn;
  int hf;
  
  if (lookup(h, name) != NULL) {
    char ebuf[1024];
    sprintf(ebuf, "Symbol %s multiply defined", name);
    yyerror(ebuf);
    return;
  }
  hf = hashfunc(name);
  hn = calloc(sizeof(struct hashnode), 1);
  hn->name = strdup(name);
  hn->val = val;
  hn->next = h->h[hf];
  h->h[hf] = hn;
}

void clear(struct hashtable *h)
{
  int i;
  struct hashnode *hn;
  for (i = 0; i < BUCKETS; ++i) {
    hn = h->h[i];
    while (hn) {
      struct hashnode *tofree = hn;
      hn = hn->next;
      free(tofree->name);
      free(tofree);
    }
    h->h[i] = NULL;
  }
}

struct typenode *binop(const struct typenode *a, const struct typenode *b)
{
  a = getPrimitiveAncestor(a);
  b = getPrimitiveAncestor(b);
  if (a == gInteger && b == gInteger)
    return gInteger;
  if ((a != gInteger && a != gReal) || (b != gInteger && b != gReal)) {
    yyerror("Bad types for binary operator");
  }
  return gReal;
}

int canconvert(const struct typenode *ufrom, const struct typenode *uto)
{
  const struct typenode *from = ufrom, *to = uto;
  char ebuf[1024];
#if 0
  if (lineno > 2400 && lineno < 2500) {
    yydebug = 1;
    fprintf(stderr, "LINE: %d\n", lineno);
  }
  else
    yydebug = 0;
#endif
  if (from == NULL || to == NULL) return 0;
  if (isDerivedFrom(from, to))
    return 1;
  /* Blizzard bug: allows downcasting erroneously */
  /* TODO: get Blizzard to fix this in Blizzard.j and the language */
  if (isDerivedFrom(to, from))
    return 1;
  if (from->typename == NULL || to->typename == NULL) return 0;
  from = getPrimitiveAncestor(from);
  to = getPrimitiveAncestor(to);
  if (from == gNull && (to == gHandle || to == gString || to == gCode))
    return 1;
  if ((from == gInteger || from == gReal) &&
      (to == gInteger || to == gReal))
    return 1;
  sprintf(ebuf, "Cannot convert %s to %s", ufrom->typename, uto->typename);
  yyerror(ebuf);
}

void checkParameters(const struct paramlist *func, const struct paramlist *inp)
{
  const struct typeandname *fi = func->head;
  const struct typeandname *pi = inp->head;
  int pnum = 1;
  for (;;) {
    if (fi == NULL && pi == NULL)
      return;
    if (fi == NULL && pi != NULL)
      yyerror("Too many arguments passed to function");
    if (fi != NULL && pi == NULL)
      yyerror("Not enough arguments passed to function");
    canconvert(pi->ty, fi->ty);
    pi = pi->next;
    fi = fi->next;
  }
}

void isnumeric(const struct typenode *ty)
{
  ty = getPrimitiveAncestor(ty);
  if (!(ty == gInteger || ty == gReal))
    yyerror("Cannot be converted to numeric type");
}

void checkcomparison(const struct typenode *a, const struct typenode *b)
{
  const struct typenode *pa, *pb;
  pa = getPrimitiveAncestor(a);
  pb = getPrimitiveAncestor(b);
  if (((pa == gString || pa == gHandle || pa == gCode) && pb == gNull) ||
      (pa == gNull && (pb == gString || pb == gCode || pb == gHandle)) ||
      (pa == gNull && pb == gNull))
    return;
  if ((pa == gReal || pa == gInteger) &&
      (pb == gReal || pb == gInteger))
    return;
  if (a != b) {
    yyerror("Objects being compared are not the same type.");
  }
}

void checkeqtest(const struct typenode *a, const struct typenode *b)
{
  checkcomparison(a, b);
}

void dofile(FILE *fp, const char *name)
{
	void *cur;
  int olderrs;
  lineno = 1;
  olderrs = haderrors;
	cur = (void *) yy_create_buffer(fp, BUFSIZE);
  yy_switch_to_buffer(cur);
  curfile = (char *) name;
	while (yyparse())
    ;
  if (olderrs == haderrors)
		printf("Parse successful: %8d lines: %s\n", lineno, curfile);
  else
		printf("%s failed with %d error%s\n", curfile, haderrors - olderrs,(haderrors == olderrs + 1) ? "" : "s");
	totlines += lineno;
}

void printversion()
{
	printf("pjass version %s by Rudi Cilibrasi\n", VERSIONSTR);
}

void doparse(int argc, char **argv)
{
  FILE *fp;
	int i;
	for (i = 1; i < argc; ++i) {
		if (argv[i][0] == '-' && argv[i][1] == 0) {
			dofile(stdin, "<stdin>");
			didparse = 1;
			continue;
		}
		if (strcmp(argv[i], "-h") == 0) {
			printversion();
printf(
"To use this program, list the files you would like to parse in order.\n"
"If you would like to parse from standard input (the keyboard), then\n"
"use - as an argument.  If you supply no arguments to pjass, it will\n"
"parse the console standard input by default.\n"
"To test this program, go into your Scripts directory, and type:\n"
"pjass common.j common.ai Blizzard.j\n"
"pjass accepts some options:\n"
"pjass -h           Display this help\n"
"pjass -v           Display version information and exit\n"
"pjass -            Read from standard input (may appear in a list)\n"
);
			exit(0);
			continue;
		}
		if (strcmp(argv[i], "-v") == 0) {
			printf("%s version %s\n", argv[0], VERSIONSTR);
			exit(0);
			continue;
		}
		fp = fopen(argv[i], "rb");
		if (fp == NULL) {
			printf("Error: Cannot open %s\n", argv[i]);
			continue;
		}
		dofile(fp, argv[i]);
		didparse = 1;
		fclose(fp);
	}
  if (argc == 1) {
		didparse = 1;
		dofile(stdin, "<stdin>");
  }
}
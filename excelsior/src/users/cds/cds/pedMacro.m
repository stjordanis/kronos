IMPLEMENTATION MODULE pedMacro; (*$U+ Sem 12-May-87. (c) KRONOS *)

FROM SYSTEM     IMPORT  WORD, ADR;

IMPORT  pcu : pedCU;
IMPORT  mdl : pedModel;

IMPORT  tty : Terminal;

CONST delta=16;

PROCEDURE clip(VAR seg: pcu.segment; X1,Y1,X2,Y2: INTEGER): BOOLEAN;
  PROCEDURE point(x1,y1,x2,y2: INTEGER; VAR x,y: INTEGER);
    VAR a,b: REAL;
  BEGIN
    a:=FLOAT((y1-y2)*(seg.x2-seg.x1));
    b:=FLOAT((seg.y1-seg.y2)*(x2-x1));
    x:=TRUNC((FLOAT(y1-seg.y1)*FLOAT(x2-x1)*FLOAT(seg.x2-seg.x1)-
              FLOAT(seg.x1)*b+FLOAT(x1)*a)/(a-b));
    y:=TRUNC((FLOAT(x1-seg.x1)*FLOAT(y2-y1)*FLOAT(seg.y2-seg.y1)-
              FLOAT(seg.y1)*a+FLOAT(y1)*b)/(b-a));
  END point;
  VAR x,y,n: INTEGER;
BEGIN
  WITH seg DO
    IF x1=x2 THEN
      IF (X1>x1) OR (X2<x1) THEN RETURN FALSE END;
      IF y2<y1 THEN y:=y1; y1:=y2; y2:=y END;
      IF (y2<Y1) OR (y1>Y2) THEN RETURN FALSE END;
      IF y1<Y1 THEN y1:=Y1 END;
      IF y2>Y2 THEN y2:=Y2 END;
    ELSIF y1=y2 THEN
      IF (Y1>y1) OR (Y2<y1) THEN RETURN FALSE END;
      IF x2<x1 THEN x:=x1; x1:=x2; x2:=x END;
      IF (x2<X1) OR (x1>X2) THEN RETURN FALSE END;
      IF x1<X1 THEN x1:=X1 END;
      IF x2>X2 THEN x2:=X2 END;
    ELSE
(* 1 *)
      point(X1,Y1,X2,Y1,x,y);
      n:=pcu.StrongSide(x1,y1,x2,y2,x,y);
      IF y1>y2 THEN n:=-n END;
      IF n>0 THEN RETURN FALSE END;
      IF n=0 THEN
        IF y1<y2 THEN x1:=x; y1:=y ELSE x2:=x; y2:=y END;
      END;
(* 2 *)
      point(X2,Y1,X2,Y2,x,y);
      n:=pcu.StrongSide(x1,y1,x2,y2,x,y);
      IF x2>x1 THEN n:=-n END;
      IF n>0 THEN RETURN FALSE END;
      IF n=0 THEN
        IF x2<x1 THEN x1:=x; y1:=y ELSE x2:=x; y2:=y END;
      END;
(* 3 *)
      point(X2,Y2,X1,Y2,x,y);
      n:=pcu.StrongSide(x1,y1,x2,y2,x,y);
      IF y2>y1 THEN n:=-n END;
      IF n>0 THEN RETURN FALSE END;
      IF n=0 THEN
        IF y2<y1 THEN x1:=x; y1:=y ELSE x2:=x; y2:=y END;
      END;
(* 4 *)
      point(X1,Y2,X1,Y1,x,y);
      n:=pcu.StrongSide(x1,y1,x2,y2,x,y);
      IF x1>x2 THEN n:=-n END;
      IF n>0 THEN RETURN FALSE END;
      IF n=0 THEN
        IF x1<x2 THEN x1:=x; y1:=y ELSE x2:=x; y2:=y END;
      END;
    END;
  END;
  RETURN TRUE;
END clip;

PROCEDURE define_macro(f: mdl.board; x1,y1,x2,y2: INTEGER;
                       VAR t: mdl.board);
  VAR i,n: INTEGER; s,s1: mdl.signal; box: pcu.range; seg: pcu.segment;
BEGIN
  mdl.cre_board(t);
  t^.x:=x2-x1+1; t^.y:=y2-y1+1; t^.lays:=f^.lays;
  IF (x1>=x2) OR (y1>=y2) THEN RETURN END;
  box.x1:=x1; box.x2:=x2; box.y1:=y1; box.y2:=y2;
  FOR i:=0 TO HIGH(f^.sigs) DO
    n:=0; s:=f^.sigs[i]; s1:=NIL;
    LOOP
      pcu.SkipSegments(s,box,n);
      IF n>HIGH(s^.cu) THEN EXIT END;
      pcu.unpack(s,n,seg); INC(n);
      IF clip(seg,x1,y1,x2,y2) THEN
        IF s1=NIL THEN
          mdl.cre_signal(s1,t);
          s1^.name:=s^.name;
        END;
        DEC(seg.x1,x1); DEC(seg.x2,x1);
        DEC(seg.y1,y1); DEC(seg.y2,y1);
        pcu.app(s1,seg);
      END;
    END;
  END;
END define_macro;

PROCEDURE NOD(x,y: INTEGER): INTEGER;
BEGIN
  x:=ABS(x); y:=ABS(y);
  IF x=0 THEN RETURN y END;
  IF y=0 THEN RETURN x END;
  LOOP IF x>y THEN x:=x-y ELSIF y>x THEN y:=y-x ELSE RETURN x END END;
END NOD;

PROCEDURE delete_box(f: mdl.board; VAR bx: pcu.range);
  VAR
    i,n,l: INTEGER;
    x,y  : INTEGER;
    dx,dy: INTEGER;
    max  : INTEGER;
    s    : mdl.signal;
    seg  : pcu.segment;
    sg1  : pcu.segment;
BEGIN
  max:=0;
  IF (bx.x1>=bx.x2) OR (bx.y1>=bx.y2) THEN RETURN END;
  FOR i:=0 TO HIGH(f^.sigs) DO
    n:=0; s:=f^.sigs[i];
    LOOP
      pcu.SkipSegments(s,bx,n);
      IF n>HIGH(s^.cu) THEN EXIT END;
      pcu.unpack(s,n,seg);
      IF seg.size>max THEN max:=seg.size END;
      WITH bx DO
        IF (seg.x1>=x1) & (seg.x1<=x2) & (seg.x2>=x1) & (seg.x2<=x2) &
           (seg.y1>=y1) & (seg.y1<=y2) & (seg.y2>=y1) & (seg.y2<=y2) THEN
          pcu.del(s,n);
        ELSIF (seg.x1<=x1) & (seg.x2<=x1) OR (seg.x1>=x2) & (seg.x2>=x2) OR
              (seg.y1<=y1) & (seg.y2<=y1) OR (seg.y1>=y2) & (seg.y2>=y2) THEN
          -- nothing
        ELSE
          pcu.del(s,n);
          dx:=seg.x2-seg.x1; dy:=seg.y2-seg.y1;
          l:=NOD(dx,dy); dx:=dx/l; dy:=dy/l;
ASSERT(seg.x1+dx*l=seg.x2);
ASSERT(seg.y1+dy*l=seg.y2);
          x:=seg.x1; y:=seg.y1;
          IF (x<x1) OR (x>x2) OR (y<y1) OR (y>y2) THEN
            REPEAT INC(x,dx); INC(y,dy) UNTIL
              (x>=x1) & (x<=x2) & (y>=y1) & (y<=y2) OR (x=seg.x2) & (y=seg.y2);
            sg1:=seg; sg1.x2:=x; sg1.y2:=y;
            pcu.app(s,sg1);
          END;
          IF (x#seg.x2) OR (y#seg.y2) THEN
            x:=seg.x2; y:=seg.y2;
            IF (x<x1) OR (x>x2) OR (y<y1) OR (y>y2) THEN
              REPEAT DEC(x,dx); DEC(y,dy) UNTIL
                (x>=x1) & (x<=x2) & (y>=y1) & (y<=y2) OR
                (x=seg.x1) & (y=seg.y1);
              sg1:=seg; sg1.x1:=x; sg1.y1:=y;
              pcu.app(s,sg1);
            END;
          END;
        END;
      END;
      INC(n);
    END;
  END;
  DEC(bx.x1,max); DEC(bx.y1,max);
  INC(bx.x2,max); INC(bx.y2,max);
END delete_box;

(*
VAR cnd: Object;
    Ident: INTEGER;
    Empty: BOOLEAN;

(*$T-*)
PROCEDURE next_conductor;
BEGIN
  IF Empty THEN RETURN END;
  INC(Ident);
  IF Ident>=cnd^.cFree THEN
    Empty:=TRUE; RETURN;
  ELSE
    Empty:=FALSE; UnPackSeg(cnd^.cType[Ident]);
  END;
END next_conductor;
(*$T+*)

PROCEDURE start_conductor(s: Object);
BEGIN
  IF s=NIL THEN Empty:=TRUE; RETURN END;
  cnd:=s^.ChainB; Ident:=-1; Empty:=FALSE;
  next_conductor;
END start_conductor;

PROCEDURE FiSi(o: Object; info: WORD);
BEGIN
  IF Tag(o)#signal THEN RETURN END;
  IF o^.Name=Key THEN Res:=o END;
END FiSi;

VAR sx,sy: INTEGER;

PROCEDURE cre_chain(sig: Object; shtd: Sheet);
  VAR sg: Object;

PROCEDURE FindSignal(nm: ARRAY OF CHAR; type: SigType): Object;
BEGIN
  Key:=nm; Res:=NIL;
  Iterate(shtd^.mdl^.All,FiSi,0);
  IF Res#NIL THEN RETURN Res END;
  Res:=NewObject(signal);
  IF (fixed  IN type) THEN INCL(Res^.sType,fixed ) END;
  IF (fantom IN type) THEN INCL(Res^.sType,fantom) END;
  IF (power  IN type) THEN INCL(Res^.sType,power ) END;
  Res^.Name:=nm; Tie(shtd^.mdl^.All,Res);
  RETURN Res;
END FindSignal;

  VAR l: INTEGER;
BEGIN
  IF Tag(sig)#signal THEN RETURN END;
  sg:=FindSignal(sig^.Name,sig^.sType);
  StartConductor(sg,FALSE);
  start_conductor(sig);
  WHILE NOT Empty DO
    LineXs:=sx+X1; LineXe:=sx+X2; LineYs:=sy+Y1; LineYe:=sy+Y2;
    IF (X1=X2)&(Y1=Y2) THEN
      IF InsertVias(Size,ViasSize,Fixed,shtd,sg,shtd^.PublicContext^.check_on)
      THEN END;
    ELSE
    IF 0 IN Layer THEN l:=0 ELSE l:=1 END;
      IF InsertRange(Size,l,Fixed,shtd,sg,shtd^.PublicContext^.check_on)
      THEN END;
    END;
    next_conductor
  END;
END cre_chain;

PROCEDURE InsertMacro(x,y: INTEGER; shtd,shts: Sheet);
BEGIN
  sx:=x; sy:=y;
  Iterate(shts^.mdl^.All,cre_chain,shtd);
END InsertMacro;

PROCEDURE InsertMetalMacro(x,y: INTEGER; shtd,shts: Sheet);
  VAR i,l,cnt,cnt1: INTEGER; b: BOOLEAN;
BEGIN
  BufPtr:=0;
  LineXs:=0; LineXe:=shts^.mdl^.ctX; LineYs:=0; LineYe:=shts^.mdl^.ctY;
  SeekInBox(shts,Seek);
  FOR i:=0 TO BufPtr-1 DO Buf[i].s1:=null END; cnt:=BufPtr;
  WHILE cnt>0 DO
    cnt1:=cnt;
    FOR i:=0 TO BufPtr-1 DO
      WITH Buf[i] DO
        FOR l:=0 TO 1 DO
          IF l IN layer THEN
            IF s1=null THEN
              LineXs:=x+x1; LineXe:=x+x2; LineYs:=y+y1; LineYe:=y+y2;
              IF Shoted?(size,l,shtd,null) THEN
                s1:=ShotedSignal;
                LineXs:=x+x1; LineXe:=x+x2; LineYs:=y+y1; LineYe:=y+y2;
                IF (x1=x2)&(y1=y2) THEN
                  b:=InsertVias(size,vias,TRUE,shtd,s1,TRUE);
                ELSE
                  b:=InsertRange(size,l,TRUE,shtd,s1,TRUE);
                END;
                DEC(cnt);
              END;
            END;
          END;
        END;
      END;
    END;
    IF cnt1=cnt THEN RETURN END;
  END;
END InsertMetalMacro;

TYPE pSegment=POINTER TO Segment;

PROCEDURE FindChip(s: Object; l: pSegment);
  PROCEDURE chk_box(p1,p2: pSegment): BOOLEAN; CODE 0F8h END chk_box;
  VAR  ch: Segment;
BEGIN
  IF Tag(s)#chip THEN RETURN END;
  CASE s^.RB OF
    -1: RETURN ;
    |0: ch.start:=s^.XB+8000h+INTEGER((s^.YB+8000h)<<16);
        ch.end  :=s^.XB+s^.ChipType^.ctX+8000h+
                  INTEGER((s^.YB+s^.ChipType^.ctY+8000h)<<16);
    |1: ch.start:=s^.XB+8000h+INTEGER((s^.YB-s^.ChipType^.ctX+8000h)<<16);
        ch.end  :=s^.XB+s^.ChipType^.ctY+8000h+INTEGER((s^.YB+8000h)<<16);
    |2: ch.start:=s^.XB-s^.ChipType^.ctX+8000h+
                  INTEGER((s^.YB-s^.ChipType^.ctY+8000h)<<16);
        ch.end  :=s^.XB+8000h+INTEGER((s^.YB+8000h)<<16);
    |3: ch.start:=s^.XB-s^.ChipType^.ctY+8000h+INTEGER((s^.YB+8000h)<<16);
        ch.end  :=s^.XB+8000h+INTEGER((s^.YB+s^.ChipType^.ctX+8000h)<<16);
  END;
  IF NOT chk_box(ADR(ch),l) THEN RETURN END;
  INC(cBufPtr);
  IF cBufPtr>HIGH(Buf) THEN
    IF NOT heap.Reallocate(cBuf^.ADR,(cBuf^.HIGH+1),cBufPtr+delta) THEN
      RaiseInMe(MemoryOverflow)
    END;
    cBuf^.HIGH:=cBufPtr+delta-1;
  END;
  cBuf[cBufPtr]:=s;
END FindChip;

PROCEDURE DefineChipMacro(sht: Sheet; x1,y1,x2,y2: INTEGER);
  VAR l: Segment;
BEGIN
  cBufPtr:=-1;
  l.start:=x1+8000h+INTEGER((y1+8000h)<<16);
  l.end  :=x2+8000h+INTEGER((y2+8000h)<<16);
  Iterate(sht^.mdl^.All,FindChip,ADR(l));
END DefineChipMacro;

PROCEDURE DoChipMacro(sht: Sheet; x,y: INTEGER; Do: chip_proc);
  VAR i: INTEGER;
BEGIN
  IF cBufPtr<0 THEN RETURN END;
  FOR i:=0 TO cBufPtr DO Do(sht,cBuf[i],x,y) END;
END DoChipMacro;

BEGIN
  BufPtr:=0; null:=NewObject(signal);
*)
END pedMacro.

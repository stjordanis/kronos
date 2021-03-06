MODULE DKwsWD; (* Leo 15-Aug-91. (c) KRONOS *)

IMPORT       SYSTEM;
IMPORT  cod: defCodes;
IMPORT   os: osKernel;
IMPORT  err: defErrors;
IMPORT  req: defRequest;
IMPORT  fs : osFiles;
IMPORT  env: tskEnv;

TYPE   bs = BITSET;
     WORD = SYSTEM.WORD;
  ADDRESS = SYSTEM.ADDRESS;

PROCEDURE di(): BITSET;  CODE cod.getm cod.copt 3 cod.bic cod.setm END di;
PROCEDURE ei(m: BITSET); CODE cod.setm END ei;

PROCEDURE self(): ADDRESS; CODE cod.activ END self;

PROCEDURE move(t,f: ADDRESS; size: INTEGER); CODE cod.move END move;
PROCEDURE transfer(VAR f,t: os.PROCESS);     CODE cod.tra  END transfer;

CONST
  ok = err.ok;

CONST
  TRIES =  8;
  VEC   = 17;

    (*   heads & tracks ONLY may be changed by SET_SPEC   *)

  (* DEFAULT DRIVE SPEC *)
  defaultHEADS    =   6;
  defaultTRACKS   = 820;

  (* FIXED   DRIVE SPEC *)
  SSC      =   9;
  SECS     =  16;
  SECSIZE  = INTEGER(1<<SSC);
  SECWORDS = SECSIZE DIV 4;

CONST
  _clear     = 80h;     _select     = 81h;
  _restore   = 82h;     _seek       = 83h;
  _read      = 84h;     _write      = 85h;
  _read_id   = 86h;     _read_track = 87h;
  _read_long = 88h;     _write_long = 89h;
  _format    = 8Ah;     _test       = 8Bh;

CONST BUF_SIZE = 4096;

VAR
  BUF: ADDRESS;            -- буфер контроллера
  KBF: POINTER TO INTEGER; -- счетчик буферов драйвера
  CBF: POINTER TO INTEGER; -- счетчик буферов контроллера
  IPT: POINTER TO INTEGER; -- сброс запроса прерываний
  CSR: POINTER TO BITSET;  -- регистр команд
 iCSR: POINTER TO INTEGER; --      --"--
  DAD: POINTER TO INTEGER; -- регистр дискового адреса
  ERR: POINTER TO BITSET;  -- регистр ошибок
 STP0: ADDRESS;
 STP1: ADDRESS;
PWOFF: BOOLEAN;

CONST
  _ERR = ARRAY OF INTEGER
         { err.prog_err, err.miss_sid, err.head_crc, err.over_run
         , err.miss_did, err.io_error, err.io_error, err.hw_fail
         , err.io_error, err.io_error, err.seek_0,   err.unsafe
         , err.not_ready };

VAR
  ports : ARRAY [0..1] OF
          RECORD
            cyls  : INTEGER;
            heads : INTEGER;
            ressec: INTEGER;
          END;

  ready : os.signal_rec;
  lockc : os.signal_rec;
  ipted : os.PROCESS;
  driver: os.PROCESS;


  OK     : BOOLEAN;

  dma    : ADDRESS;
  dma_len: INTEGER;
  dma_cou: INTEGER;

  dma0    : ADDRESS;
  dma_len0: INTEGER;

  triger : INTEGER;

  cdu    : INTEGER; (* disk unit            *)
  cofs   : INTEGER; (* first sector in cash *)
  clen   : INTEGER; (* sectors in cash      *)

  cbuf   : ARRAY [0..4095] OF CHAR;

PROCEDURE cashunlock;
  VAR m: BITSET;
BEGIN
  m:=di();
    IF lockc.cou=0 THEN os.send(lockc) END;
  ei(m)
END cashunlock;

PROCEDURE read_buffer;
BEGIN
  IF (CBF^<0) OR (CBF^>=7) OR (dma_len0=0) THEN
    CSR^:=CSR^-{28..30}; triger:=IPT^;
    CSR^:=bs(_clear>>8);
    os.send(ready);
    cashunlock; cdu:=-1;
    RETURN
  END;
  LOOP
    IF (dma_cou=CBF^) & (iCSR^<0) THEN RETURN END;
    IF dma_len>0 THEN
      move(dma,BUF+dma_cou*SECWORDS,SECWORDS);
      INC (dma,SECWORDS);  DEC(dma_len);
      IF dma_len=0  THEN OK:=TRUE; os.send(ready) END
    ELSE
      move(dma0,BUF+dma_cou*SECWORDS,SECWORDS);
      INC (dma0,SECWORDS)
    END;
    DEC(dma_len0);
    IF dma_len0=0  THEN
      CSR^:=CSR^-{28..30}; triger:=IPT^;
      CSR^:=bs(_clear>>8);
      cashunlock;
      RETURN
    END;
    dma_cou:=(dma_cou+1) MOD 7;  KBF^:=dma_cou
  END
END read_buffer;

PROCEDURE interrupt;
BEGIN
  LOOP
    triger:=IPT^;
    IF CSR^*{24..27}={26} THEN
      read_buffer
    ELSIF iCSR^>=0 THEN
      (* write_buffer *)
      CSR^:=CSR^-{28..30}; triger:=IPT^;
      CSR^:=bs(_clear>>8);
      IF ready.queue#os.null THEN os.send(ready) END
    END;
    transfer(driver,ipted)
  END
END interrupt;

PROCEDURE exec(c: BITSET): INTEGER;
  VAR i,r: INTEGER;
      drn: INTEGER;
      ero: BITSET;
      m,x: BITSET;
BEGIN
  drn:=INTEGER((c>>16)*{0..7});
  m:=di();
    REPEAT UNTIL iCSR^>=0;

    OK := FALSE;

    CSR^:=c;     r:=os.wait_del(200,ready);

    IF OK THEN ei(m); RETURN ok END;

    i:=iCSR^;  ero:=ERR^;
    IF (r=0) & (ero*{7}={}) & (i>=0) THEN ei(m); RETURN ok END;
                                          -----
    triger:=IPT^; ready.cou:=0; lockc.cou:=1; cdu:=-1;
  ei(m);
  IF (r<0) OR (i<0) THEN RETURN err.time_out END;
  i:=0;   x:=BITSET(err.io_error);   ero:=ero>>8;
  REPEAT
    IF ero*{0}#{} THEN x:=x+BITSET(_ERR[i]) END;
    i:=i+1;  ero:=ero>>1
  UNTIL i>HIGH(_ERR);
  RETURN INTEGER(x)
END exec;

PROCEDURE restore(drn: INTEGER);
BEGIN
--  IF exec({28..31}+bs(_restore<<24)+bs(drn<<16))#ok THEN END
END restore;

PROCEDURE read(VAR r: req.REQUEST);
  VAR trk: INTEGER;
      res: INTEGER;    sec: INTEGER;
     l,sc: INTEGER;    len: INTEGER;
     head: INTEGER;    spr: INTEGER;
BEGIN
  r.res:=0;
  WITH ports[r.drn] DO
    dma :=r.buf;
    len :=r.len; r.len:=0;
    spr :=SECS; (* sectors per request *)
    sec:=r.ofs;
    LOOP
      trk :=sec DIV SECS;
      head:=trk MOD heads;
      trk :=trk DIV heads;
      sc  :=sec MOD SECS;
      IF len<=spr THEN l:=len ELSE l:=spr END;
      dma_cou :=0;
      dma_len :=l;
      dma_len0:=l;
      dma0    :=SYSTEM.ADR(cbuf);
      IF sc+l<SECS THEN
        cdu :=r.drn;
        cofs:=sec+l;
        clen:=SECS-sc-l;     IF clen>8 THEN clen:=8 END;
        INC(dma_len0,clen);
        lockc.cou:=0
      END;
      CBF^:=0;
      KBF^:=0;

      DAD^:=(head MOD 8)*10000h+trk;

      IF head>7 THEN
        STP0^:=000F0000h;
        STP1^:=000F0000h
      ELSE
        STP0^:=000F0FFFh;
        STP1^:=000F0FFFh
      END;

      res :=exec({28..31}+bs(_read>>8)+bs(r.drn<<16)+bs(sc<<8)+bs(dma_len0));
      r.res:=INTEGER(BITSET(r.res)+BITSET(res));
      IF dma_len#0 THEN
        r.res:=INTEGER(BITSET(r.res)+BITSET(err.no_data)); RETURN
      END;
      INC(sec,l); (* dma was allready incremented by interrupt handler *)
      INC(r.len,l); DEC(len,l);
      IF len=0 THEN RETURN END;
    END
  END
END read;

PROCEDURE write(VAR r: req.REQUEST);
  VAR trk: INTEGER;
      res: INTEGER;    sec: INTEGER;
     l,sc: INTEGER;    len: INTEGER;
     head: INTEGER;    spr: INTEGER;
BEGIN
  r.res:=ok;
  WITH ports[r.drn] DO
    dma:=r.buf;     dma_len:=0;
    len:=r.len; r.len:=0;
    spr:=BUF_SIZE DIV SECSIZE - 1; (* sectors per request (less then read) *)
    sec:=r.ofs;
    LOOP
      trk :=sec DIV SECS;
      head:=trk MOD heads;
      trk :=trk DIV heads;
      sc  :=sec MOD SECS;
      IF len<=spr THEN l:=len ELSE l:=spr END;
      CBF^:=0; KBF^:=l-1;

      DAD^:=(head MOD 8)*10000h+trk;

      IF head>7 THEN
        STP0^:=000F0000h;
        STP1^:=000F0000h
      ELSE
        STP0^:=000F0FFFh;
        STP1^:=000F0FFFh
      END;

      move(BUF,dma,l*SECWORDS);
      res :=exec({28..31}+bs(_write>>8)+bs(r.drn<<16)+bs(sc<<8)+bs(l));
      r.res:=INTEGER(BITSET(r.res)+BITSET(res));
      DEC(len,l); INC(r.len,l);
      IF len=0 THEN RETURN END;
      INC(sec,l); INC(dma,l*SECWORDS)
    END
  END
END write;

PROCEDURE FORMAT(VAR r: req.REQUEST);
  VAR head,trk: INTEGER;
BEGIN
  cdu:=-1;
  IF r.ofs<0 THEN restore(r.drn); RETURN END;
  WITH ports[r.drn] DO
    r.ofs:=r.ofs+ressec;
    trk  :=r.ofs DIV SECS;
    head :=trk   MOD heads;
    trk  :=trk   DIV heads;
    CBF^ :=0;
    KBF^ :=0;    dma_len:=0;

    DAD^:=(head MOD 8)*10000h+trk;

    IF head>7 THEN
      STP0^:=000F0000h;
      STP1^:=000F0000h
    ELSE
      STP0^:=000F0FFFh;
      STP1^:=000F0FFFh
    END;

    r.res:=exec({28..31}+bs(_format>>8)+bs(r.drn<<16));
  END
END FORMAT;

PROCEDURE lockcash;
  VAR m: BITSET;
BEGIN
  m:=di();
    IF lockc.cou=0 THEN os.wait(lockc); lockc.cou:=1 END;
  ei(m)
END lockcash;

PROCEDURE READ(VAR r: req.REQUEST);
  VAR t,len: INTEGER;
BEGIN
  t:=TRIES; len:=r.len;
  IF len<=0 THEN r.res:=err.bad_parm; RETURN END;
  r.ofs:=r.ofs+ports[r.drn].ressec;
  IF (cdu=r.drn) & (r.ofs>=cofs) & ((r.ofs+r.len)<=(cofs+clen)) THEN
    move(r.buf,SYSTEM.ADR(cbuf)+(r.ofs-cofs)*128,r.len*128); RETURN
  END;
  LOOP
    read(r); DEC(t);
    IF (r.res=ok) OR (t=0)  THEN RETURN END;
    lockcash;
    IF t MOD 2 = 0 THEN  restore(r.drn) END;
    r.len:=len;  r.res:=ok
  END
END READ;

PROCEDURE WRITE(VAR r: req.REQUEST);
  VAR t,len: INTEGER;
BEGIN
  t:=TRIES; len:=r.len;
  IF len<=0 THEN r.res:=err.bad_parm; RETURN END;
  r.ofs:=r.ofs+ports[r.drn].ressec;
  IF (cdu=r.drn) & (r.ofs<(cofs+clen)) & (r.ofs+r.len>cofs) THEN cdu:=-1 END;
  LOOP
    write(r); DEC(t);
    IF (r.res=ok) OR (t=0)  THEN RETURN END;
    IF t MOD 2 = 0 THEN restore(r.drn)  END;
    r.len:=len;  r.res:=ok
  END
END WRITE;

PROCEDURE SEEK(VAR r: req.REQUEST);
BEGIN
  r.ofs:=r.ofs+ports[r.drn].ressec;
  r.buf:=BUF; r.len:=1; read(r)
END SEEK;

PROCEDURE park(VAR r: req.REQUEST);
BEGIN
  WITH ports[r.drn] DO
    r.buf:=BUF;
    r.ofs:=cyls*heads*SECS-1;
    r.len:=1
  END;
  read(r); PWOFF:=TRUE; cdu:=-1
END park;

PROCEDURE get_spec(VAR r: req.REQUEST);
BEGIN
  WITH ports[r.drn] DO
    r.dmode :=req.ready+req.wint+req.fmttrk;
    r.ssc   :=SSC;       r.secsize:=SECSIZE;
    r.minsec:=0;         r.maxsec :=SECS-1;
    r.cyls  :=cyls;      r.ressec :=ressec;
    r.heads :=heads;     r.precomp:=0;
    r.rate  :=0;         r.dsecs  :=heads*cyls*SECS-ressec
  END
END get_spec;

PROCEDURE set_spec(VAR r: req.REQUEST);
BEGIN
  WITH ports[r.drn] DO
    heads :=r.heads;
    cyls  :=r.cyls;
    ressec:=r.ressec
  END
END set_spec;

PROCEDURE mount(VAR r: req.REQUEST);
  VAR s: req.REQUEST;
    LAB: POINTER TO ARRAY [0..31] OF CHAR;
BEGIN
  LAB:=r.buf; r.len:=1; r.ofs:=0;
  read(r);
  IF r.res#ok THEN lockcash; read(r) END;
  IF r.res#ok THEN RETURN  END;
  IF (LAB^[8+0]#"X") OR (LAB^[8+1]#"D") OR (LAB^[8+2]#"0") THEN RETURN END;
  s.drn   :=r.drn;
  get_spec(s);
  s.res   :=ok;
  s.cyls  :=ORD(LAB^[8+4])+ORD(LAB^[8+5])*256;
  s.heads :=ORD(LAB^[8+8]);
  s.ressec:=ORD(LAB^[8+10]);
  set_spec(s);
  r.res:=s.res
END mount;

PROCEDURE doio(VAR r: req.REQUEST);
BEGIN
  IF PWOFF & (r.op#req.POWER_OFF) THEN r.res:=err.ill_access; RETURN END;
  r.res:=ok;
  lockcash;
  CASE r.op OF
    |req.READ     : READ(r)
    |req.WRITE    : WRITE(r)
    |req.SEEK     : SEEK(r)
    |req.MOUNT    : mount(r)
    |req.UNMOUNT  : restore(r.drn)
    |req.POWER_OFF: park(r);
    |req.SET_SPEC : set_spec(r)
    |req.GET_SPEC : get_spec(r)
    |req.FORMAT   : FORMAT(r)
  ELSE
    r.res:=err.inv_op
  END
END doio;

PROCEDURE final;
BEGIN
  IF fs.remove_driver("wd0")#ok THEN END;
  IF fs.remove_driver("wd1")#ok THEN END
END final;

PROCEDURE define(TRK,HDS,RES: INTEGER);
  VAR i: INTEGER;
      m: BITSET;
    adr: ADDRESS;
    stp: ADDRESS;
BEGIN
  BUF:=ADDRESS(900000h);
  KBF:=ADDRESS(9003F6h);
  CBF:=ADDRESS(9003F7h);
  CSR:=ADDRESS(9003FFh);  iCSR:=ADDRESS(CSR);
  DAD:=ADDRESS(9003FEh);
  ERR:=ADDRESS(9003FDh);
  IPT:=ADDRESS(900400h);

  STP0:=9003FBh;
  STP1:=9003FAh;

  STP0^:=000F0FFFh;
  IF STP0^=0 THEN HALT(err.not_ready) END;
  STP1^:=000F0FFFh;

  dma:=NIL; dma0:=NIL; cofs:=-1; clen:=-1;
  dma_len:=0; dma_len0:=0; dma_cou:=0;  PWOFF:=FALSE; cdu:=-1;

  FOR i:=0 TO 1 DO
    WITH ports[i] DO
      heads:=HDS;  cyls:=TRK;  ressec:=RES;
    END
  END;
  os.ini_signal(ready,{},0);
  os.ini_signal(lockc,{},1);

  env.final(final);
  i:=fs.define_driver("wd0","wd0",0,fs.disk,doio);
  IF i#ok THEN HALT(i) END;
  i:=fs.define_driver("wd1","wd0",1,fs.disk,doio);
  IF i#ok THEN HALT(i) END;
  env.put_str(env.info,"wd0 wd1",TRUE)
END define;

PROCEDURE waitIPT;
  VAR m: BITSET;
    adr: ADDRESS;
BEGIN
  m:=di();
  driver:=self();
  adr:=VEC*2; adr^:=driver;
  adr:=adr+1; adr^:=SYSTEM.ADR(ipted);
  env.become_ipr;
  os.suspend(os.active(),-1);
  interrupt
END waitIPT;

BEGIN
  define(defaultTRACKS,defaultHEADS,0);
  waitIPT
END DKwsWD.

  VEC = 17;

  ADR    BYTE
  9003FF.0   sector count
  9003FF.1   first sector number
  9003FF.2   drive
  9003FF.3   bits 0..3 - op. code:
                cmd_clear     = 0
                cmd_select    = 1
                cmd_restore   = 2
                cmd_seek      = 3
                cmd_read      = 4
                cmd_write     = 5
                cmd_read_id   = 6
                cmd_read_track= 7
                cmd_read_long = 8
                cmd_write_long= 9
                cmd_format    = A
                cmd_test      = B
             bit 4
             bit 5
             bit 6
             bit 7  -  ready = 0, busy (start) = 1

  9003FE.0 \
  9003FE.1 / cylinder
  9003FE.2   head
  9003FE.3
  9003FD.0 error
             bits 0..6 - buffer with error
             bit 7 - common error flag
  9003FD.1 error code 0
         8   bit 0 - invalid op. code                (prog_err)
         9   bit 1 - ID not found after 256 tries    (miss_sid)
        10   bit 2 - ID ECC error                    (head_crc)
        11   bit 3 - buffer not ready                (over_run)
        12   bit 4 - data AM not found               (miss_did)
        13
        14
        15   bit 7 - WR FAULT from drive             (hw_fail)
  9003FD.2 error code 1
        16
        17
        18   bit 2 - seek incomplete after 0.63 ms   (seek00)
        19   bit 3 - restore fail                    (unsafe)
        20   bit 4 - drive not ready                 (not_ready)

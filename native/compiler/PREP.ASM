;==========================================================================
;  Preparing a compilation
;==========================================================================
;
;  The PREP overlay (OVERLAY.ASM): the state a compilation begins with,
;  made once, after the start-up has loaded the parts and opened the
;  streams. PR_BUILD (ROUTINES.ASM) loads NAMES first and then runs PREP
;  above it, so that PREP can read IoError's member spellings from NAMES
;  (D54). It runs inside PR_BUILD, whose saved SP a diagnostic returns to,
;  so the memory's check may raise DG_ROOM here as anywhere in the parse.
;
;  Principal entries:
;    PP_RUN    clear the parse state, place the tables and declare IoError

PP_SPEL EQU  AC_RVAL           ; Word: the next IoError member's spelling in NAMES.
PP_HEAD EQU  AC_RVAL+2         ; Word: the member node made last, the list's head.
PP_ORD EQU  AC_RVAL+4          ; Byte: the next member's ordinal.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Clear the state one compilation accumulates: the diagnostic, the
; lookahead, the symbol table's chains, the forward flag, the aggregate
; counters, the next ordinal (the program's base, $0400) and the largest
; frame. Then place the tables, owing no line end: the name heap starts
; below the part table, and the symbol table above the largest part,
; rounded up to whole 128-byte records, which is where each part is loaded
; (SY_BTM); no constant waits above it yet (RG_CBEG, RG_PEND). If the
; symbol table's first record would reach the name heap, the memory is
; full (DG_ROOM). Then clear the pools' table, the owner descriptors'
; ordinals and the routine state, and declare IoError, the services'
; failure enum, as the first type (AG_FIRST).

PP_RUN:                        ; Runs above NAMES, through OV_XCALL.
    XOR  A                         ; A is zero for the byte fields cleared below.
    LD   H,A                       ; HL is zero for the word fields:
    LD   L,A                       ; set both halves.
    LD   (DG_CODE),HL              ; No diagnostic yet, and no failing part (DG_PART).
    LD   (RG_LARGE),HL             ; No frame yet: the largest frame is zero bytes.
    LD   (SY_BODY),HL              ; No routine body is open.
    LD   (RG_FWD),A                ; No forward routine is outstanding.
    LD   (EX_PRIME),A              ; No primary has been parsed ahead.
    LD   HL,$0400                  ; The program's first blob ordinal
    LD   (RG_ORD),HL               ; is the next ordinal to give out.
    LD   HL,SY_HTAB                ; Every symbol hash chain head,
    LD   B,2*SY_HCAP               ; two bytes each,
    CALL .WIPE                     ; is cleared: every chain starts empty.
    LD   HL,AG_DCNT                ; The aggregate counters, AG_DCNT to AG_OPENF,
    LD   B,AG_OPENF-AG_DCNT+1      ; this many bytes,
    CALL .WIPE                     ; start at zero.
    DEC  A                         ; A is $FF, the empty-lookahead marker:
    LD   (PR_LKIND),A              ; no token is buffered.
    LD   A,(SRC_PCNT)              ; The part table's last entry is number
    DEC  A                         ; count less one;
    CALL SRC_PART                  ; HL addresses that entry,
    LD   (NH_PTR),HL               ; and the name heap grows down from below it.
    LD   BC,0                      ; BC will be the longest part's length.
    LD   A,(SRC_PCNT)              ; A counts the parts still to measure.
.LARGE:                        ; Measure the next part down.
    DEC  A                         ; Step to the next entry down.
    PUSH AF                        ; Keep the count across the measurement.
    CALL SRC_PART                  ; HL addresses the part's entry; BC is kept.
    LD   DE,PT_START               ; Step to the entry's start word,
    ADD  HL,DE                     ; which the end word follows.
    CALL WD_GET                    ; DE is the part's start; HL is at its end word.
    LD   A,(HL)                    ; Read the end word's low byte,
    INC  HL                        ; step to its high byte,
    LD   H,(HL)                    ; read it into H,
    LD   L,A                       ; and put the low byte in L: HL is the end.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; HL is the part's length.
    PUSH HL                        ; Keep the length while comparing.
    SBC  HL,BC                     ; Carry if it is shorter than the longest so far.
    POP  HL                        ; The length again.
    JR   C,.SHORT                  ; Shorter: keep the longest so far.
    LD   B,H                       ; Longer or equal: it is the longest now,
    LD   C,L                       ; in BC.
.SHORT:                        ; Go on to the next part.
    POP  AF                        ; The count of parts still to measure.
    JR   NZ,.LARGE                 ; Measure the next, down to entry zero.
    LD   HL,127                    ; Round the longest length up to whole
    ADD  HL,BC                     ; 128-byte records: add 127,
    LD   A,L                       ; then clear the low seven bits
    AND  $80                       ; of the sum's low byte,
    LD   L,A                       ; keeping the rounded length in HL.
    LD   DE,MM_SRC                 ; Parts load at MM_SRC, so the symbol table
    ADD  HL,DE                     ; begins that rounded length above it.
    LD   (SY_BTM),HL               ; The symbol table's bottom
    LD   (SY_TOP),HL               ; and top are both there: it is empty.
    LD   DE,SY_RECB                ; Leave room for the provisional record,
    ADD  HL,DE                     ; the first record written.
    LD   (RG_CBEG),HL              ; No aggregate constant waits yet:
    LD   (RG_PEND),HL              ; their area starts and ends here.
    EX   DE,HL                     ; DE is where that area starts.
    LD   HL,(NH_PTR)               ; Compare it with the name heap's bottom:
    OR   A                         ; clear carry,
    SBC  HL,DE                     ; and carry if the area would reach the heap.
    JR   NC,.FITS                  ; Room enough: continue.
    XOR  A                         ; The memory is full: no part is current,
    LD   (SRC_ID),A                ; so the diagnostic names none,
    JP   MM_FULL                   ; and DG_ROOM is raised.
.FITS:                         ; The tables are placed.
    XOR  A                         ; No line end is owed
    LD   (SRC_OWE),A               ; at a part's boundary.
    LD   HL,PL_CNT                 ; Clear the pools' count and table; a
    LD   B,FW_TAB-PL_CNT           ; frame's flows are cleared as the frame
    CALL .WIPE                     ; opens (FW_OPEN).
    LD   HL,PL_DESC                ; Clear the owner descriptors' ordinals,
    LD   B,2*AG_TCAP               ; one word a type:
    CALL .WIPE                     ; none is written yet.
    LD   HL,RO_BASE                ; Clear the routine state: its counts,
    LD   B,RO_SPAR-RO_BASE         ; fields, hash chains and the record
    CALL .WIPE                     ; of the signature being parsed.

; IoError (D54), the services' failure enum, is declared as EN_DECL
; (ENDECL.ASM) declares an enum: its name retained, each member a node in
; the name heap whose spelling is in NAMES (HP_IOS, its length from
; IO_LENS, IOERRS.ASM), then its descriptor and its type name's symbol.

    LD   HL,PP_NAME                ; Make "IoError", held here,
    LD   (TK_PTR),HL               ; the current name token,
    LD   A,7                       ; seven bytes long,
    LD   (TK_LEN),A                ; for the declaration helpers;
    CALL EX_KEEP                   ; retain it, copied into the name heap.
    LD   HL,(OV_AREA)              ; NAMES begins with the address of the
    LD   (PP_SPEL),HL              ; member spellings: start at the first.
    LD   HL,0                      ; No member node yet:
    LD   (PP_HEAD),HL              ; the list is empty.
    XOR  A                         ; Start at the first ordinal,
    LD   (PP_ORD),A                ; zero.
.MEMBER:                       ; Make the node of member PP_ORD.
    LD   BC,6                      ; A node is six bytes:
    CALL NH_ALLOC                  ; DE addresses it, in the name heap.
    LD   HL,(PP_HEAD)              ; The previous head becomes this node's next,
    LD   (PP_HEAD),DE              ; and this node becomes the head.
    PUSH HL                        ; Keep the next node's address for later.
    LD   A,(PP_ORD)                ; Look up this member's length in IO_LENS,
    LD   L,A                       ; indexed by its ordinal:
    LD   H,0                       ; the ordinal as a word,
    LD   BC,IO_LENS                ; plus the table's address,
    ADD  HL,BC                     ; addresses the length,
    LD   C,(HL)                    ; which goes to C.
    LD   HL,(PP_SPEL)              ; HL is the spelling's first byte in NAMES.
    PUSH HL                        ; Keep it to store in the node.
    LD   B,0                       ; The next member's spelling follows this
    ADD  HL,BC                     ; one directly, C bytes on;
    LD   (PP_SPEL),HL              ; keep its address for the next member.
    POP  HL                        ; HL is this spelling's address again;
    EX   DE,HL                     ; move it to DE, and HL to the node.
    LD   (HL),E                    ; Node +0: the spelling's address, low byte,
    INC  HL                        ; then
    LD   (HL),D                    ; its high byte.
    INC  HL                        ; Node +2:
    LD   (HL),C                    ; the spelling's length.
    INC  HL                        ; Node +3:
    LD   A,(PP_ORD)                ; the member's ordinal,
    LD   (HL),A                    ; stored.
    INC  HL                        ; Node +4: the next node's address,
    POP  DE                        ; taken back from the stack,
    LD   (HL),E                    ; low byte,
    INC  HL                        ; then
    LD   (HL),D                    ; high byte.
    INC  A                         ; Advance to the next ordinal
    LD   (PP_ORD),A                ; and keep it.
    CP   IO_COUNT                  ; Until every member is made,
    JR   NZ,.MEMBER                ; make the next.
    LD   HL,(PP_HEAD)              ; The descriptor's member list starts
    LD   (AG_NDIM),HL              ; at the node made last.
    LD   A,IO_COUNT                ; Its member count
    LD   (AG_NAUX),A               ; is IO_COUNT.
    LD   A,AG_KENUM                ; Its kind
    LD   (AG_NKIND),A              ; is an enum's.
    LD   HL,1                      ; A value of it
    LD   (AG_NSIZE),HL             ; takes one byte.
    CALL AG_ADD                    ; Add the type: A is its ID, AG_FIRST.
    LD   C,A                       ; The type name's symbol has the ID
    LD   B,0                       ; as its payload
    LD   D,SY_TYPE                 ; and the type-name class.
    CALL EX_PREP                   ; Write the symbol provisionally,
    JP   SY_CMT                    ; then commit it and return.

;@ROUTINE IN B,HL OUT A CLOBBERS B,HL,ZERO,SIGN,PARITY,HALFCARRY,CARRY
; Clear B bytes at HL. A is zero after.

.WIPE:                         ; HL is the first byte, B the count.
    XOR  A                         ; Zero is the value stored.
.ZERO:                         ; Clear one byte:
    LD   (HL),A                    ; store zero,
    INC  HL                        ; move to the next byte,
    DJNZ .ZERO                     ; and repeat B times.
    RET                            ; Done.

PP_NAME: DB  "IoError"         ; The services' failure enum's name.

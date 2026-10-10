; Nominal enums share the dynamic type table, but are byte scalars.
; Members live in the existing name heap: spelling word, length, ordinal,
; next word. Their names are qualified and never enter global hash chains.
; Declaration scratch reuses initializer scratch, unavailable concurrently.
EN_HEAD EQU AG_IBUF            ; Word: newest member.
EN_COUNT EQU AG_IBUF+2         ; Word: members seen, 1..256.

; A kept; carry iff a built-in scalar or a nominal enum. BC,DE,HL kept.
AG_SCAL:
    CP   AG_FIRST
    RET  C
    CP   AG_FIRST+AG_TCAP
    JR   NC,.OTHER
    PUSH BC
    PUSH DE
    PUSH HL
    LD   C,A
    CALL AG_KIND                   ; Its descriptor in HL, its kind in A.
    CP   AG_KENUM
    LD   A,C
    POP  HL
    POP  DE
    POP  BC
    SCF
    RET  Z
.OTHER:
    OR   A
    RET

; A full type and D storage class -> D packed symbol information.
; BC,E,HL kept. Parameter flags are meaningful only for aggregates.
SY_KIND:
    CALL AG_SCAL
    JR   NC,.AGGR
    CP   AG_FIRST
    JR   C,.SCALAR
    LD   A,SY_ENUM
.SCALAR:
    RES  7,D                     ; Only aggregate parameter flags use bit 7.
    OR   D
    LD   D,A
    RET
.AGGR:
    SET  7,D
    RET

; Decode packed scalar A; HL is SY_GET's payload high byte. Registers
; other than A kept. The tag follows at HL+1.
EN_STYPE:
    AND  SY_TMASK
    CP   SY_ENUM
    RET  NZ
    INC  HL
    LD   A,(HL)
    DEC  HL
    RET

; Current token's spelling in member list HL; carry iff found, HL node.
EN_FIND:
    LD   A,H
    OR   L
    RET  Z
    CALL TK_SAME
    RET  C
    LD   DE,4
    ADD  HL,DE
    CALL WD_GET
    EX   DE,HL
    JR   EN_FIND

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY
; Island EnumDeclaration, after `enum`: the ENUMS overlay's entry (ED_RUN,
; ENDECL.ASM), run above NAMES through OV_XCALL.

EN_DECL:                       ; After `enum`.
    XOR  A                         ; Entry 0
    LD   B,OV_ENUMS                ; of ENUMS
    JP   OV_XCALL                  ; runs; it returns.

; A type name's payload BC. Resolve its qualified member as known enum.
; Non-enum names retain the existing wrong-class diagnostic.
EN_MEM:                        ; D is the name's class byte, BC its payload.
    LD   A,D                       ; Load the class byte.
    CP   SY_TYPE                   ; Only a type name is exactly SY_TYPE; a pool adds SY_GLOB.
    JR   NZ,.CLASS                 ; Anything else is wrong-class.
    LD   A,C                       ; A is the type's ID, the payload's low byte.
    CALL AG_KIND                   ; Its descriptor in HL, its kind in A.
    CP   AG_KENUM                  ; Is it an enum?
.CLASS:                        ; Not an enum type: zero clear here.
    LD   A,DG_CLASS                ; The diagnostic is wrong-class;
    JP   NZ,DG_NAMED               ; raise it, naming the type, unless an enum.
    PUSH BC                        ; Keep the enum's ID for the member's value.
    LD   HL,(TK_POS)               ; Keep the type name's offset: the peek below
    PUSH HL                        ; moves TK_POS to the next token.
    CALL PR_PEEK                   ; Look at the token after the type name.
    CP   TK_DOT                    ; Is it `.`, a qualified member?
    JR   Z,.QUAL                   ; Then read the member.
    POP  HL                        ; No: the type name alone is no value.
    PUSH HL                        ; Keep its offset on the stack again.
    LD   A,DG_CLASS                ; The diagnostic is wrong-class,
    CALL DG_WORD                   ; naming the type, as argument 1.
    POP  HL                        ; HL is the type name's offset,
    JP   DG_HERE                   ; where wrong-class is raised; no return.
.QUAL:                         ; A qualified member follows.
    POP  HL                        ; Drop the saved offset.
    CALL PR_TAKE                   ; Consume `.`.
    CALL RO_NAME                   ; Take the member's name.
    POP  BC                        ; Recover the enum's ID
    PUSH BC                        ; and keep it again.
    LD   A,C                       ; A is the enum's ID.
    CALL AG_DESC                   ; HL addresses its descriptor.
    INC  HL                        ; Step past the kind
    INC  HL                        ; and the member count
    CALL WD_GET                    ; to the member list's head, read into DE.
    EX   DE,HL                     ; HL heads the member list.
    CALL EN_FIND                   ; Find the member's name: carry and HL its node.
    JP   NC,SY_UNDEF               ; Not a member: undeclared-name, naming it.
    INC  HL                        ; Step past the spelling's address
    INC  HL                        ; and length
    INC  HL                        ; to the node's ordinal.
    LD   L,(HL)                    ; L is the member's ordinal,
    LD   H,0                       ; and HL its value as a word.
    POP  BC                        ; Recover the enum's ID in C.
    LD   B,C                       ; B is the value's metadata: the enum type,
    SET  7,B                       ; known (bit 7), a constant.
    JP   EX_LIT                    ; Return the member as a known constant.

;==========================================================================
;  Enum declarations
;==========================================================================
;
;  Overlay ENUMS, loaded above NAMES in FLOAT's place when a program
;  declares an enum (EN_DECL, ENUMS.ASM, through OV_XCALL), which a program
;  does once per type, at top level. Its members live in the name heap
;  (ENUMS.ASM): a node of six bytes each, the spelling's word and length,
;  the ordinal and the next node, newest first; their names are qualified
;  and never enter the hash chains. Its scratch, EN_HEAD and EN_COUNT, is
;  the initializers' (AG_IBUF), unused while it runs. An f32 literal read
;  here loads FLOAT over it, and OV_XCALL loads it again before returning.
;
;  Principal entry:
;    ED_RUN    the EnumDeclaration island, at the overlay's start

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY
; Island EnumDeclaration: the name, retained and declared (EX_DECL), its
; line's end, then member lines until `end`, each a name not yet a member
; (duplicate-name at it) and at most 256 (capacity at it), then `end` and
; its line's end. No member is empty-enum at the declaration. The type is
; a new descriptor (AG_KENUM, its count, zero for 256, and its member list)
; and its name a type symbol (SY_TYPE) of the new ID.

ED_RUN:                        ; After `enum`.
    CALL RO_NAME                   ; Take the enum's name.
    CALL EX_DECL                   ; Retain it and check it is not already declared.
    LD   E,TK_EOL                  ; Expect the end of the line next:
    CALL PR_NEED                   ; consume it, or report syntax.
    LD   HL,0                      ; Zero, for the two fields below.
    LD   (EN_HEAD),HL              ; The member list is empty.
    LD   (EN_COUNT),HL             ; No member is counted yet.
.MEMBER:                       ; Each line is a member's name, or `end`.
    CALL PR_PEEK                   ; Look at the line's first token.
    CP   TK_END                    ; Is it `end`?
    JR   Z,.END                    ; Then finish the declaration.
    CALL RO_NAME                   ; Take the member's name.
    LD   HL,(EN_HEAD)              ; HL heads the members declared so far.
    CALL EN_FIND                   ; Carry if one has this name's spelling.
    LD   A,DG_DUP                  ; The diagnostic is duplicate-name;
    JP   C,DG_NAMED                ; raise it, naming the member, if found.
    LD   A,(EN_COUNT+1)            ; Load the count's high byte, set at 256;
    OR   A                         ; it is nonzero if 256 are counted already.
    LD   A,DG_EMEM                 ; The diagnostic is capacity (enum members);
    JP   NZ,DG_ISSUE               ; raise it if there is no room for another.
    LD   BC,6                      ; A member's node is six bytes.
    CALL NH_ALLOC                  ; Allocate it in the name heap: DE is its address.
    PUSH DE                        ; Keep the node's address.
    EX   DE,HL                     ; HL addresses the node.
    CALL TK_KEEP                   ; Node +0..+2: the spelling's address and length.
    INC  HL                        ; Step to node +3, the ordinal.
    LD   DE,(EN_COUNT)             ; Load the count of members before this one;
    LD   (HL),E                    ; its low byte is this member's ordinal.
    INC  DE                        ; Count this member.
    LD   (EN_COUNT),DE             ; Store the new count.
    INC  HL                        ; Step to node +4, the next node's address.
    LD   DE,(EN_HEAD)              ; Load the current head of the list.
    LD   (HL),E                    ; Store its low byte as the next node's address,
    INC  HL                        ; step to the high byte,
    LD   (HL),D                    ; and store the high byte.
    POP  HL                        ; Recover the new node's address.
    LD   (EN_HEAD),HL              ; It becomes the head of the list.
    LD   E,TK_EOL                  ; Expect the end of the line next:
    CALL PR_NEED                   ; consume it, or report syntax.
    JR   .MEMBER                   ; Read the next line.
.END:                          ; `end` reached.
    LD   HL,(EN_COUNT)             ; Load the member count.
    LD   A,H                       ; Copy its high byte to A
    OR   L                         ; and OR in the low byte: zero if no member.
    LD   A,DG_EENUM                ; The diagnostic is empty-enum.
    JR   NZ,.NONEMPTY              ; With a member, go on to declare the type.
    LD   HL,AC_DPOS                ; HL addresses the declaration's position.
    JP   DG_AT                     ; Raise empty-enum there; no return.
.NONEMPTY:                     ; Declare the type.
    LD   A,L                       ; The count's low byte, zero for 256 members,
    LD   (AG_NAUX),A               ; is the descriptor's auxiliary byte.
    LD   A,AG_KENUM                ; The descriptor's kind is AG_KENUM,
    LD   (AG_NKIND),A              ; stored in the candidate descriptor.
    LD   HL,(EN_HEAD)              ; Load the head of the member list
    LD   (AG_NDIM),HL              ; as the descriptor's member list.
    LD   HL,1                      ; An enum value takes one byte,
    LD   (AG_NSIZE),HL             ; the type's size.
    CALL AG_ADD                    ; Add the type: A is its new ID.
    LD   C,A                       ; C is the new ID, the symbol's payload;
    LD   B,0                       ; B, its high byte, is zero.
    LD   D,SY_TYPE                 ; D is the type-name class.
    CALL EX_PREP                   ; Write the type name's provisional symbol.
    CALL SY_CMT                    ; Commit it to the symbol table.
    CALL PR_TAKE                   ; Consume `end`.
    LD   E,TK_EOL                  ; Expect the end of the line next:
    JP   PR_NEED                   ; consume it, or report syntax; return.

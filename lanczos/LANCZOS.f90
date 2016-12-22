    SUBROUTINE LANCZOS(A,B,MAXA,R,EIGV,NN,NNM,NWK,NWM,NROOT,RTOL,NC,NNC,NITEM,IFSS,IFPR,NSTIF,IOUT)
! . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
! .
! .   P R O G R A M
! .   TO SOLVE FOR THE SMALLEST EIGENVALUES-- ASSUMED .GT. 0 --
! .   AND CORRESPONDING EIGENVECTORS IN THE GENERALIZED
! .   EIGENPROBLEM USING THE Lanczos METHOD
! .   
! .   - - INPUT VARIABLES - -
! .   A(NWK) = STIFFNESS MATRIX IN COMPACTED FORM (ASSUMED
! .            POSITIVE DEFINITE)
! .   B(NWM) = MASS MATRIX IN COMPACTED FORM
! .   MAXA(NNM) = VECTOR CONTAINING ADDRESSES OF DIAGONAL
! .               ELEMENTS OF STIFFNESS MATRIX A
! .   R(NN,NROOT) = STORAGE FOR EIGENVECTORS
! .   EIGV(NROOT) = STORAGE FOR EIGENVALUES
! .   Q(NN,NC) = working matrix
! .   AR(NNC) = WORKING MATRIX STORING PROJECTION OF K
! .   BR(NNC) = WORKING MATRIX STORING PROJECTION OF M
! .   VEC(NC,NC) = WORKING MATRIX
! .   TT(NN) = WORKING VECTOR
! .   W(NN) = WORKING VECTOR
! .   D(NC) = WORKING VECTOR
! .   RTOLV(NC) = WORKING VECTOR
! .   BUP(NC) = WORKING VECTOR
! .   BLO(NC) = WORKING VECTOR
! .   BUPC(NC) = WORKING VECTOR
! .   NN = ORDER OF STIFFNESS AND MASS MATRICES
! .   NNM = NN + 1
! .   NWK = NUMBER OF ELEMENTS BELOW SKYLINE OF
! .            STIFFNESS MATRIX
! .   NWM = NUMBER OF ELEMENTS BELOW SKYLINE OF
! .          MASS MATRIX
! .   I. E. NWM=NWK FOR CONSISTENT MASS MATRIX
! .         NWM=NN FOR LUMPED MASS MATRIX
! .   NROOT = NUMBER OF REQUIRED EIGENVALUES AND EIGENVECTORS.
! .   RTOL = CONVERGENCE TOLERANCE ON EIGENVALUES
! .             ( 1.E-09 OR SMALLER )
! .   NC = NUMBER OF ITERATION VECTORS USED
! .           (USUALLY SET TO MIN(2*NROOT, NROOT+8), BUT NC
! .           CANNOT BE LARGER THAN THE NUMBER OF MASS
! .        DEGREES OF FREEDOM)
! .   NNC = NC*(NC+1)/2 DIMENSION OF STORAGE VECTORS AR,BR
! .   NITEM = MAXIMUM NUMBER OF RESTART
! .              (USUALLY SET TO 5)
! .   THE PARAMETERS NC AND/OR NITEM MUST BE
! .   INCREASED IF A SOLUTION HAS NOT CONVERGED
! .   IFSS = FLAG FOR STURM SEQUENCE CHECK
! .             EQ.0 NO CHECK
! .             EQ.1 CHECK
! .   IFPR = FLAG FOR PRINTING DURING ITERATION
! .           EQ.0 NO PRINTING
! .           EQ.1 PRINT
! .   NSTIF = SCRATCH FILE
! .   IOUT = UNIT USED FOR OUTPUT
! .   
! .   - - OUTPUT - -
! .   EIGV(NROOT) = EIGENVALUES
! .   R(NN,NROOT) = EIGENVECTORS
! .
! . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
!
    IMPLICIT NONE
    INTEGER, INTENT(IN) :: NN,NNM,NWK,NWM,NROOT,NC,NNC,NITEM
    INTEGER, INTENT(IN) :: MAXA(NNM),IFPR,NSTIF,IOUT
    INTEGER, INTENT(INOUT) :: IFSS
    REAL(8), INTENT(IN) :: B(NWM)
    REAL(8), INTENT(IN) :: BUP(NC)
    REAL(8), INTENT(IN) :: BLO(NC),BUPC(NC),RTOL
    REAL(8), INTENT(INOUT) :: A(NWK),AR(NNC),BR(NNC),VEC(NC,NC)
    REAL(8), INTENT(INOUT) :: EIGV(NROOT),R(NN,NROOT)
    REAL(8), INTENT(INOUT) :: D(NC),RTOLV(NC),W(NN),TT(NN)
    REAL(8) :: Q(NN,NC),DOT,DOT_PRODUCT
    REAL(8) :: ART,BRT,TOLJ,TOLJ2,RT,BT,PI,XX,SHIFT
    REAL(8) :: VECT,VNORM,WNORM,EIGVT,ALPHA,BETA
    INTEGER :: ICONV,NSCH,NSMAX,N1,NC1,I,J,K,L,II,IX
    INTEGER :: ITEMP,IS,ISH,NMIS,NITE,NEI
!
! SET TOLERANCE FOR JACOBI
!
    TOLJ = 1.D-12
    REWIND NSTIF
    WRITE (NSTIF) A
!    
! INITIALIZATION
!
    N1=NC+1
    ICONV = 0  
    NITE = 0
    NSMAX = 12
!
! CHECK THE MASS MATRIX
!
    IF(NWM .LE. NN) THEN
      J=0
      DO K=1,NN
        IF(B(K).GT.0) J=J + 1
      END DO
      IF(NC.GT.J) THEN
        WRITE (IOUT,1007)
        STOP
      END IF
    END IF
!
! - - - LOOP FOR RESTART - - -
!
    DO WHILE (ICONV.LT.NROOT .AND. NITE.LE.NITEM) 

      NITE=NITE + 1
      IF (IFPR.NE.0) WRITE (IOUT,1010) NITE

      REWIND NSTIF
      READ (NSTIF) A
!
! SET THE SHIFT
!
      IF(NITE.NE.1.AND.ICONV.GT.0)THEN
        IF(ICONV.EQ.1) THEN 
          SHIFT = EIGV(ICONV)/2.0
        ELSE
          SHIFT = (EIGV(ICONV)+EIGV(ICONV-1))/2.0
        END IF
        IF(NWM.EQ.NN)THEN
          DO I=1,NN
            II=MAXA(I)
            A(II)=A(II) - SHIFT*B(I)
          END DO
        ELSE
          DO I=1,NN
            II=MAXA(I)
            A(II)=A(II) - SHIFT*B(II)
          END DO
        END IF
      END IF
!
! FACTORIZE MATRIX A INTO (L)*(D)*(L(T))
!
      ISH=0
      CALL DECOMP (A,MAXA,NN,ISH,IOUT)
!
! ESTABLISH STARTING ITERATION VECTORS
!

      PI=3.141592654D0
      XX=0.5D0
      DO K=1,NN
        XX=(PI + XX)**5
        IX=INT(XX)
        XX=XX - FLOAT(IX)
        W(K)=XX
      END DO
!
! SET ZEROS MATRIX: AR AND UNIT DIAG MATRIX: BR
!
      DO I=1,NNC
        AR(I)=0.0D0
        BR(I)=0.0D0
      END DO
      DO I=1,NC
        J=(2*N1-I)*(I-1)/2+1
        BR(J)=1.0D0
      END DO 
!
! ORTHOGONALIZATION 
!
      CALL ORTHMGS(Q(1,1),0,R(1,1),NROOT,ICONV,NN,B(1),NWM,MAXA,W,TT)
!
! UNITFIED COORDING TO MASS MASTRIX
!
      CALL MULT(TT,B(1),W,MAXA,NN,NWM)
      BETA = SQRT(DOT_PRODUCT(W,TT))
      DO J=1,NN
        Q(J,1)=W(J)/BETA
      END DO
!
! - - - Loop for nc vectors - - -
!
      DO I = 2, NC+1
!
! SET THE RIGHT HAND VECTOR
!
        CALL MULT(TT,B(1),Q(1,I-1),MAXA,NN,NWM)
        DO J=1,NN
          W(J)=TT(J)
        END DO
!
! BACK SUBSTITUE AND SOLVE THE EQUATION
!
        CALL REDBAK (A,W,MAXA,NN)
!
! Calculate the parameter of ALPHA AND STORE IN AR
!
        ALPHA = DOT_PRODUCT(W,TT)
        J=(2*N1-I+1)*(I-2)/2+1
        AR(J) = ALPHA
!
! ORTHOGONALIZATION  
!  
        IF(I.EQ.2)THEN
          DO J=1,NN
            W(J) = W(J)-ALPHA*Q(J,I-1)
          END DO
        ELSE
           J=(2*N1-I+2)*(I-3)/2+2
          BETA=AR(J) 
          DO J=1,NN
            W(J) = W(J)-ALPHA*Q(J,I-1)-BETA*Q(J,I-2)
          END DO
        END IF
!
! RE-ORTHOGONALIZATION 
!
        CALL ORTHMGS(Q(1,1),I-1,R(1,1),NROOT,ICONV,NN,B(1),NWM,MAXA,W,TT)
!
! CALCULATE THE PARAMETER BETA AND UNITFIED COORDING TO MASS MASTRIX
!
        CALL MULT(TT,B(1),W,MAXA,NN,NWM)
        BETA = SQRT(DOT_PRODUCT(W,TT))
        IF(I.NE.NC+1)THEN
          J=(2*N1-I+1)*(I-2)/2+2 
          AR(J) = BETA
          DO J=1,NN
            Q(J,I)=W(J)/BETA
          END DO
        END IF
      END DO
!--------- END OF THE LOOP OF VECTORE--------------
!
! SOLVE FOR EIGENSYSTEM OF OPERATORS three orginzed
!
      CALL JACOBI(AR,BR,VEC,D,TT,NC,NNC,TOLJ,NSMAX,IFPR,IOUT)
!
! ARRANGE EIGENVALUES IN DESCENDING ORDER FOR D
!
      DO
      IS=0
      II=1
      DO I=1,NC-1
        ITEMP=II + N1 - I
        IF (D(I+1).LE.D(I)) CYCLE
        IS=IS + 1
        EIGVT=D(I+1)
        D(I+1)=D(I)
        D(I)=EIGVT
        DO K=1,NC
          VECT=VEC(K,I+1)
          VEC(K,I+1)=VEC(K,I)
          VEC(K,I)=VECT
        END DO
        II=ITEMP
      END DO
      IF (IS.LE.0) EXIT
      END DO
!
! CHECK FOR CONVERGENCE OF EIGENVALUES AND CALCULATE THE EIGEN VECTOR
!
      DO J=1,NC
        RTOLV(J)= ABS(BETA*VEC(J,NC))
        IF(RTOLV(J).LE.RTOL.AND.ICONV.LT.NROOT) THEN
          ICONV=ICONV+1
          EIGV(ICONV)=1.0D0/D(J)+SHIFT
          DO K=1,NN
            R(K,ICONV) = 0.0
            DO L=1,NC
              R(K,ICONV)=R(K,ICONV)+Q(K,L)*VEC(L,J)
            END DO !L
          END DO !K
        END IF
      END DO
!
      IF (IFPR.NE.0 .OR. ICONV.NE.0) THEN
        WRITE (IOUT,1050) NITE
        WRITE (IOUT,1005) (RTOLV(I),I=1,NC)
      END IF
!
! ARRANGE EIGENVALUES IN ASCENDING ORDER FOR R
!
      DO
      IS=0
      II=1
      DO I=1,ICONV-1
        ITEMP=II + N1 - I
        IF (EIGV(I+1).GE.EIGV(I)) CYCLE
        IS=IS + 1
        EIGVT=EIGV(I+1)
        EIGV(I+1)=EIGV(I)
        EIGV(I)=EIGVT
        DO K=1,NN
          RT=R(K,I+1)
          R(K,I+1)=R(K,I)
          R(K,I)=RT
        END DO
        II=ITEMP
      END DO
      IF (IS.LE.0) EXIT
      END DO
!
      IF (IFPR.NE.0) THEN
        WRITE (IOUT,1035)
        WRITE (IOUT,1006) (EIGV(I),I=1,NC)
      END IF

    END DO
!
! - - - E N D O F I T E R A T I O N L O O P
!
    WRITE (IOUT,1090) NROOT,ICONV
    IF(ICONV.GT.0) THEN
      WRITE (IOUT,1100)
      WRITE (IOUT,1006) (EIGV(I),I=1,NROOT)
      WRITE (IOUT,1110)
      DO J=1,NROOT
        WRITE (IOUT,1005) (R(K,J),K=1,NN)
      END DO
    END IF

! THE LAST RESTART AND STORE THE UNCONVERCED RESULT
    IF(NITE.GE.NITEM.AND.ICONV.LT.NROOT) THEN
        WRITE (IOUT,1070)
        IFSS=0
        DO J=1,NC
!          RTOLV(J)= ABS(BETA*VEC(J,NC))
          IF(RTOLV(J).GT.RTOL.AND.ICONV.LT.NROOT) THEN   ! NOT DEAL BEFORE
            ICONV=ICONV+1
            EIGV(ICONV)=1.0D0/D(J)+SHIFT
            DO K=1,NN
              R(K,ICONV) = 0.0
              DO L=1,NC
                R(K,ICONV)=R(K,ICONV)+Q(K,L)*VEC(L,J)
              END DO !L
            END DO !K
          END IF
        END DO
        WRITE (IOUT,1100)
        WRITE (IOUT,1006) (EIGV(I),I=1,NROOT)
        WRITE (IOUT,1110)
        DO J=1,NROOT
          WRITE (IOUT,1005) (R(K,J),K=1,NN)
        END DO
    END IF
!
! CALCULATE AND PRINT ERROR MEASURES
!
    REWIND NSTIF
    READ (NSTIF) A
!
    DO L=1,NROOT
      RT=EIGV(L)
      CALL MULT(TT,A,R(1,L),MAXA,NN,NWK)
      VNORM=0.0
      DO I=1,NN
        VNORM=VNORM + TT(I)*TT(I)
      END DO
      CALL MULT(W,B,R(1,L),MAXA,NN,NWM)
      WNORM=0.
      DO I=1,NN
        TT(I)=TT(I) - RT*W(I)
        WNORM=WNORM + TT(I)*TT(I)
      END DO
      VNORM=SQRT(VNORM)
      WNORM=SQRT(WNORM)
      D(L)=WNORM/VNORM
    END DO
!
    WRITE (IOUT,1115)
    WRITE (IOUT,1005) (D(I),I=1,NROOT)
!
! APPLY STURM SEQUENCE CHECK
!
    IF (IFSS.EQ.0) RETURN
    CALL SCHECK(EIGV,RTOLV,BUP,BLO,BUPC,D,NC,NEI,RTOL,SHIFT,IOUT)
!
    WRITE (IOUT,1120) SHIFT
!
! SHIFT MATRIX A
!
    REWIND NSTIF
    READ (NSTIF) A
!
    IF (NWM.LE.NN) THEN
      DO I=1,NN
        II=MAXA(I)
        A(II)=A(II) - B(I)*SHIFT
      END DO
    ELSE
      DO I=1,NWK
        A(I)=A(I) - B(I)*SHIFT
      END DO
    END IF
!
! FACTORIZE SHIFTED MATRIX
!
    ISH=1
    CALL DECOMP (A,MAXA,NN,ISH,IOUT)
!
! COUNT NUMBER OF NEGATIVE DIAGONAL ELEMENTS
!
    NSCH=0
    DO I=1,NN
      II=MAXA(I)
      IF (A(II).LT.0.) NSCH=NSCH + 1
    END DO
!
    IF (NSCH.NE.NEI) THEN
      NMIS=NSCH - NEI
      WRITE (IOUT,1130) NMIS
    ELSE
      WRITE (IOUT,1140) NSCH
    END IF
!
    RETURN

1002 FORMAT (' ',10F10.0)
1005 FORMAT (' ',12E11.4)
1006 FORMAT (' ',6E22.14)
1007 FORMAT (///,' STOP, NC IS LARGER THAN THE NUMBER OF MASS ', &
                 'DEGREES OF FREEDOM')
1008 FORMAT (///,' DEGREES OF FREEDOM EXCITED BY UNIT STARTING ', &
                 'ITERATION VECTORS')
1010 FORMAT (//,' I T E R A T I O N N U M B E R ',I8)
1035 FORMAT (/,' EIGENVALUES OF AR-LAMBDA*BR')
1040 FORMAT (//,' AR AND BR AFTER JACOBI DIAGONALIZATION')
1050 FORMAT (/,' ERROR BOUNDS REACHED ON EIGENVALUES AT RESTART OF',I5)
1060 FORMAT (///,' CONVERGENCE REACHED FOR RTOL ',E10.4)
1070 FORMAT (' *** NO OR INSUFFICIENCY CONVERGENCE IN MAXIMUM NUMBER OF ITERATIONS', &
             ' PERMITTED',/, &
             ' WE ACCEPT CURRENT ITERATION VALUES',/, &
             ' THE STURM SEQUENCE CHECK IS NOT PERFORMED')
1090 FORMAT (//, ' DEGREES OF EIGEN IS', I5, &
             ' THE NUMBER OF CONVERGENCD IS',I5)
1100 FORMAT (///,' THE CALCULATED EIGENVALUES ARE')
1115 FORMAT (//,' ERROR MEASURES ON THE EIGENVALUES')
1110 FORMAT (//,' THE CALCULATED EIGENVECTORS ARE',/)
1120 FORMAT (///,' CHECK APPLIED AT SHIFT ',E22.14)
1130 FORMAT (//,' THERE ARE ',I8,' EIGENVALUES MISSING')
1140 FORMAT (//,' WE FOUND THE LOWEST ',I8,' EIGENVALUES')
    END



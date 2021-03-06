!===========================================================================================
! 
! HEXAHEDRAL ELEMENT SUBROUTINE INCLUDING:
!    8H Data Read in
!    8H Element Stiffness Matrix Assembly
!    Post-processing from Displacements
! 
! future support for 27H will be added.
! 
! Author:    Haoguang Yang
! 
!===========================================================================================
subroutine HexTriQuad
    use globals
    use memallocate
    
    implicit none
    integer :: NumberOfElements, NumberOfMaterials, ElementGroupSize, QuadratureOrder=2
    integer :: N(11) !Pointers
    
    NPAR(5) = 20
    NPAR(4) = 0
    
    NumberOfElements = NPAR(2)
    NumberOfMaterials = NPAR(3)
    
    !Preallocate Memory
    
!pointer lists
! Calculate the pointer to the arrays in the element group data
! N101: E(NumberOfMaterials)
! N102: v(NumberOfMaterials)
! N103: Density(NumberOfMaterials)
! N104: Gravity(NumberOfMaterials)
! N105: LM(3*NPAR(5),NumberOfElements)
! N106: PositionData(3*NPAR(5),NumberOfElements)
! N107: MaterialData(NumberOfElements)
! N108: BMat (NumberOfElements*18*NPAR(5)*8)
! N109: Jacobian(NumberOfElements*QuadratureOrder^3)

    N(1) = 0
    N(2) = N(1)+NumberOfMaterials*ITWO
    N(3) = N(2)+NumberOfMaterials*ITWO
    
    if (NPAR(4) .GT. 0) then
        N(4) = N(3)+NumberOfMaterials*ITWO
        N(5) = N(4)+NumberOfMaterials*ITWO
    else
        N(4) = N(3)
        N(5) = N(4)
    end if
    
    N(6) = N(5) + 3*NPAR(5)*NumberOfElements
    N(7) = N(6) + 3*NPAR(5)*NumberOfElements*ITWO
    N(8) = N(7) + NumberOfElements
    N(9) = N(8) + NPAR(5)*NPAR(2)
    
    MIDEST = N(9)
    
    if (IND .EQ. 1) then
        call MemAlloc(11,"ELEGP",MIDEST,1)
        !call MemAlloc(6,"NODE ",NPAR(5)*NPAR(2),1)
    end if
    NFIRST = NP(11)
    N(:) = N(:) + NFIRST
    NLAST  = N(9)
    
    call HexTwn (IA(NP(1)),DA(NP(2)),DA(NP(3)),DA(NP(4)),DA(NP(4)),IA(NP(5)),   &
                  A(N(1)),A(N(2)),A(N(3)),A(N(4)),A(N(5)),A(N(6)),A(N(7)),A(N(8)))
    
    !Reuse DA(NP(4)) at Solution Phase 3 as displacement U
    return
end subroutine HexTriQuad

subroutine HexTwn (ID,X,Y,Z,U,MHT,E, PoissonRatio, Density, Gravity, LM, PositionData, MaterialData, Node)
    use globals
    use MemAllocate
    use MathKernel
    
    implicit none
    integer ::  ElementShapeNodes, NumberOfMaterials, NumberOfElements
    integer ::  QuadratureOrder     = 3                     ! NPAR(6) -- Element Load Nodes
    INTEGER ::  ID(6,NUMNP), MHT(NEQ), MaterialData(NPAR(2))
    integer ::  MaterialType, MaterialComp, ND, L, N, i, j, LM(24,NPAR(2)), ElementType, ind0, iprint, k, &
                ind1, ind2, Node(NPAR(2),NPAR(5))
    real(8) ::  X(NUMNP), Y(NUMNP), Z(NUMNP), U(NEQ), &
                DetJ(3,3,3), E(NPAR(3)), PoissonRatio(NPAR(3)), ElementDisp(81)
    real(8) ::  BMatrix(6, 3*NPAR(5)), PositionData(3*NPAR(5), NPAR(2)), DMatrix(6,6), &
                Transformed(3), W(3), Weight(3,3,3), GaussianPts(3), GaussianCollection(3, NPAR(2)*3**3), &
                StressCollection(6,NPAR(2)*3**3), M(3*NPAR(5),3*NPAR(5)), Rho
    real(8) ::  Young, v, S(3*NPAR(5),3*NPAR(5)), GaussianPtsPosit(3,3**3), Strain(6,3**3), Stress(6,3**3), &
                Density, Gravity, NMatrix(3,3*NPAR(5)), NormalVec(3), Point(3*NPAR(5),3*NPAR(5))
                
    ElementType         = NPAR(1)
    NumberOfElements    = NPAR(2)
    NumberOfMaterials   = NPAR(3)
    ElementShapeNodes   = NPAR(5)                           !NPAR(5)=27
    ND = 81
    
    SELECT CASE (IND)
    CASE(1)
        WRITE (IOUT,"(' E L E M E N T   D E F I N I T I O N',//,  &
                   ' ELEMENT TYPE ',13(' .'),'( NPAR(1) ) . . =',I10,/,   &
                   '     EQ.1, TRUSS ELEMENTS',/,       &
                   '     EQ.2, 2D TRIANGLE',/,          &
                   '     EQ.3, 2D QUADRANGLE',/,        &
                   '     EQ.4, 3D HEXAHEDRAL',//,       &
                   ' NUMBER OF ELEMENTS.',10(' .'),'( NPAR(2) ) . . =',I10,/)") ElementType, NumberOfElements
        IF (NumberOfMaterials.EQ.0) NumberOfMaterials=1
        WRITE (IOUT,"(' M A T E R I A L   D E F I N I T I O N',//,  &
                   ' NUMBER OF DIFFERENT SETS OF MATERIAL',/,  &
                   ' AND CROSS-SECTIONAL  CONSTANTS ',         &
                   4 (' .'),'( NPAR(3) ) . . =',I10,/)") NumberOfMaterials
        
        WRITE (IOUT,"('  SET       YOUNG''S    POISSON',/,  & 
                            ' NUMBER     MODULUS      RATIO',/,  &
                   15 X,'E', 12 X, 'v')")

        DO I=1,NumberOfMaterials
            READ (IIN,'(I10,2F10.0)') N,E(N), PoissonRatio(N)      ! Read material information for 3D Homogeneous
            WRITE (IOUT,"(I10,4X,E12.5,2X,E14.6)") N,E(N), PoissonRatio(N)
        END DO
        WRITE (IOUT,"(//,' E L E M E N T   I N F O R M A T I O N',//,  &
                      ' ELEMENT        |------------------------- NODES -------------------------|       MATERIAL',/,   &
                      ' NUMBER-N        1       2       3       4       5       6       7       8       SET NUMBER')")
        N=0
        
        CALL GaussianMask(GaussianPts, W, QuadratureOrder)
        
        DO WHILE (N .NE. NumberOfElements)
            READ (IIN,'(11I10)') N,Node(N,1:NPAR(5)),MaterialType          ! Read in element information
            
    !       Save element information
            PositionData(1:ElementShapeNodes*3-1:3,N)=X(Node(N,:))        ! Coordinates of the element's nodes
            PositionData(2:ElementShapeNodes*3  :3,N)=Y(Node(N,:))
            PositionData(3:ElementShapeNodes*3+1:3,N)=Z(Node(N,:))
            
            MaterialData(N) = MaterialType                                ! Material type

            DO L=1,ND
                LM(L,N)=0
            END DO
            DO L=1,3
                LM(L:ElementShapeNodes*3+L-2:3,N) = ID(L,Node(N,:))       ! Connectivity matrix
            END DO
            
            
            if (.NOT. PARDISODOOR) CALL COLHT (MHT,ND,LM(:,N))
            WRITE (IOUT,"(I7,5X,7(I7,1X),I7,4X,I10)") N,Node(N,1:ElementShapeNodes),MaterialType
            
            !write (IOUT,*) 'MHT',MHT
            write (VTKNodeTmp) NPAR(5), Node(N,:)-1
            
        enddo
        return
    
    CASE (2)
        CALL GaussianMask(GaussianPts, W, QuadratureOrder)
        do i = 1, QuadratureOrder
            do j = 1, QuadratureOrder
                do k = 1, QuadratureOrder
                    Weight(i,j,k)  = W(i)*W(j)*W(k)
                end do
            end do
        end do
        
        MaterialComp = -1
        do N = 1, NumberOfElements
            S(:,:) = 0
            MaterialType = MaterialData(N)
            if (MaterialType .NE. MaterialComp) then
                Young        = E(MaterialType)
                v            = PoissonRatio(MaterialType)
                call GetDMat(Young, v, DMatrix)
                IF (DYNANALYSIS .EQV. .TRUE.) Rho = Density(MaterialType)
                MaterialComp = MaterialType
            end if
            
            !DetJ = reshape(Jacobian((n-1)*QuadratureOrder**3+1 : n*QuadratureOrder**3), &
            !               (/QuadratureOrder, QuadratureOrder, QuadratureOrder/))
            DetJ(:, :, :)=0
            do i = 1, QuadratureOrder
                do j = 1, QuadratureOrder
                    do k = 1, QuadratureOrder
                        Transformed   = (/GaussianPts(i), GaussianPts(j), GaussianPts(k)/)
                        CALL HexB27 (BMatrix, DetJ(i,j,k), ElementShapeNodes, Transformed, &
                                  (/PositionData(1:ElementShapeNodes*3-1:3,N), &
                                    PositionData(2:ElementShapeNodes*3  :3,N), &
                                    PositionData(3:ElementShapeNodes*3+1:3,N)/))
                        Point   = matmul(matmul(transpose(BMatrix),DMatrix),BMatrix)
                        S = S + (Weight(i,j,k)*DetJ(i,j,k))*Point
                        IF (DYNANALYSIS .EQV. .TRUE.) then
                            call HexN27 (NMatrix, ElementShapeNodes, Transformed)             !Initialize N Matrix for mass assembly
                            Point = Rho*matmul(transpose(NMatrix),NMatrix)
                            M = M + (Weight(i,j,k)*DetJ(i,j,k))*Point
                        END IF
                    end do
                end do
            end do
            
            !write(*,*) "S",S
            
<<<<<<< HEAD

=======
<<<<<<< HEAD
            if(pardisodoor) then
                IF (DYNANALYSIS) call pardiso_addban(DA(NP(10)),IA(NP(2)),IA(NP(5)),S,LM(:,N),ND)
            else
                call ADDBAN(DA(NP(3)),IA(NP(2)),S,LM(:,N),ND)
                IF (DYNANALYSIS) CALL ADDBAN (DA(NP(10)),IA(NP(2)),M,LM(:,N),ND)
            end if
=======
>>>>>>> dedcc6447c9449ac1dd2040a1e7b5f4a73482371
            !CALL ADDBAN (DA(NP(3)),IA(NP(2)),S,LM(:,N),ND)
            if(pardisodoor) then
                call pardiso_addban(DA(NP(3)),IA(NP(2)),IA(NP(5)),S,LM(1,N),ND)
                if (DYNANALYSIS) CALL pardiso_addban(DA(NP(10)),IA(NP(9)), IA(NP(8)),M,LM(:,N),ND)
            else
                CALL ADDBAN (DA(NP(3)),IA(NP(2)),S,LM(1,N),ND)
                IF (DYNANALYSIS .EQV. .TRUE.) CALL ADDBAN (DA(NP(5)),IA(NP(2)),M,LM(:,N),ND)
            end if
            
<<<<<<< HEAD

=======
>>>>>>> c85d1edd52a173423583b01cc6524492827c80cd
>>>>>>> dedcc6447c9449ac1dd2040a1e7b5f4a73482371
            
        end do
        
    CASE (3)
        
        IPRINT=0
        call GaussianMask(GaussianPts, W, QuadratureOrder)
        DO N=1,NumberOfElements
            IPRINT=IPRINT + 1
            IF (IPRINT.GT.50) IPRINT=1
            IF (IPRINT.EQ.1) WRITE (IOUT,"(//,' S T R E S S  C A L C U L A T I O N S  F O R  ',  &
                                           'E L E M E N T  G R O U P',I4,//,   &
            '  ELEMENT',13X, 'COORDINSTES',19X, 'Sigma_xx',9X, 'Sigma_yy',9X,'Sigma_zz',9X, &
            'Sigma_xy',9X,'Sigma_yz',9X,'Sigma_xz', /, &
            '  NUMBER', 8X,'X',10X,'Y',10X,'Z')") NG
            MaterialType = MaterialData(N)
            Young        = E(MaterialType)
            v            = PoissonRatio(MaterialType)
            call GetDMat(Young, v, DMatrix)
            
            ElementDisp(:) = 0
            
            do i = 1,ND
                if (LM(i,N) .NE. 0) ElementDisp(i)  =  U(LM(i,N))
            end do
            
            ind0 = 1
            do i = 1,QuadratureOrder
                do j = 1,QuadratureOrder
                    do k = 1,QuadratureOrder
                        Transformed   = (/GaussianPts(i), GaussianPts(j), GaussianPts(k)/)
                        call HexN27 (NMatrix, ElementShapeNodes, Transformed)
                        GaussianPtsPosit(:,ind0) = matmul(reshape(PositionData(:,N), (/3,ElementShapeNodes/)), &
                                                         NMatrix(1, 1:3*ElementShapeNodes:3))
                        CALL HexB27 (BMatrix, DetJ(i,j,k), ElementShapeNodes, Transformed, &
                                  (/PositionData(1:ElementShapeNodes*3-1:3,N), &
                                    PositionData(2:ElementShapeNodes*3  :3,N), &
                                    PositionData(3:ElementShapeNodes*3+1:3,N)/))
                        Strain(:,ind0) = matmul(BMatrix, ElementDisp)             
                        Stress(:,ind0) = matmul(DMatrix, Strain(:,ind0))
                        
                        ind0 = ind0 + 1
                    end do
                end do
            end do
            
            write (IOUT,"(I6,3(3X, F10.4),6(4X, E13.6),/,7(6X, 3(3X, F10.4),6(4X, E13.6),/))") &
                               N, (GaussianPtsPosit(:,I), Stress(:,I), I=1,QuadratureOrder**3)
            ind1 = (N-1)*QuadratureOrder**3+1
            ind2 = N*QuadratureOrder**3
            GaussianCollection (:,ind1:ind2) = GaussianPtsPosit
            StressCollection (:,ind1:ind2) = Stress
        END DO

        call PostProcessor(ElementType, 3, PositionData, &
                           Node, QuadratureOrder**3, GaussianCollection, StressCollection, U)
                           
                
    END SELECT

end subroutine HexTwn


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!              Calculate Shape Function Matrix             !!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
subroutine HexN27 (NMatrix, ElementShapeNodes, Transformed)
    implicit none
    integer ::  ElementShapeNodes, i
    real(8) ::  NMatrix(3, 3*ElementShapeNodes), Transformed(3), N(ElementShapeNodes)
    real(8) :: xi, eta, zta
    
    xi = Transformed(1)
    eta = Transformed(2)
    zta = Transformed(3)
    select case (ElementShapeNodes)
    case (20)
    !>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>WORKING PROGRESS
        N(1) = (1-xi)*(1-eta)*(1-zta)*(-xi-eta-zta-2)/8
        N(2) = (1+xi)*(1-eta)*(1-zta)*(xi-eta-zta-2)/8
        N(3) = (1+xi)*(1+eta)*(1-zta)*(+xi+eta-zta-2)/8
        N(4) = (1-xi)*(1+eta)*(1-zta)*(-xi+eta-zta-2)/8
        N(5) = (1-xi)*(1-eta)*(1+zta)*(-xi-eta+zta-2)/8
        N(6) = (1+xi)*(1-eta)*(1+zta)*(xi-eta+zta-2)/8
        N(7) = (1+xi)*(1+eta)*(1+zta)*(xi+eta+zta-2)/8
        N(8) = (1-xi)*(1+eta)*(1+zta)*(-xi+eta+zta-2)/8
        N(9) = (1-xi**2)*(1-eta)*(1-zta)/4
        N(10) = (1-xi**2)*(1+eta)*(1-zta)/4
        N(11) = (1-xi**2)*(1+eta)*(1+zta)/4
        N(12) = (1-xi**2)*(1-eta)*(1+zta)/4
        N(13) = (1-eta**2)*(1-xi)*(1-zta)/4
        N(14) = (1-eta**2)*(1+xi)*(1-zta)/4
        N(15) = (1-eta**2)*(1+xi)*(1+zta)/4
        N(16) = (1-eta**2)*(1-xi)*(1+zta)/4
        N(17) = (1-zta**2)*(1-xi)*(1-eta)/4
        N(18) = (1-zta**2)*(1+xi)*(1-eta)/4
        N(19) = (1-zta**2)*(1+xi)*(1+eta)/4
        N(20) = (1-zta**2)*(1-xi)*(1+eta)/4
        NMatrix = reshape((/((/N(i), 0D0, 0D0, 0D0, N(i), 0D0, 0D0, 0D0, N(i)/),i=1,ElementShapeNodes)/), &
                          shape(NMatrix))
    end select
end subroutine HexN27


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!       Calculate Gradiient of Shape Function Matrix       !!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

subroutine HexB27 (BMatrix, DetJ, ElementShapeNodes, Transformed, Original)
    USE MathKernel
    implicit none
    integer, intent(in) ::  ElementShapeNodes
    real(8) ::  BMatrix(6, 3*ElementShapeNodes), DetJ, Transformed(3), Original(ElementShapeNodes, 3)
    real(8) ::  GradN(3,ElementShapeNodes), J(3,3), InvMatJ(3,3), DerivN(3,ElementShapeNodes)
    real(8) ::  Bx(ElementShapeNodes), By(ElementShapeNodes), Bz(ElementShapeNodes), xi, eta, zta
    integer ::  i
    logical ::  OK_Flag
    
    select case (ElementShapeNodes)
    case (20)
    !>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>WORKING PROGRESS
        xi      = Transformed(1)
        eta     = Transformed(2)
        zta     = Transformed(3)
        GradN   = 0.125*reshape((/-(1-eta)*(1-zta), -(1-xi)*(1-zta), -(1-xi)*(1-eta), &
                                   (1-eta)*(1-zta), -(1+xi)*(1-zta), -(1+xi)*(1-eta), &
                                   (1+eta)*(1-zta),  (1+xi)*(1-zta), -(1+xi)*(1+eta), &
                                  -(1+eta)*(1-zta),  (1-xi)*(1-zta), -(1-xi)*(1+eta), &
                                  -(1-eta)*(1+zta), -(1-xi)*(1+zta),  (1-xi)*(1-eta), &
                                   (1-eta)*(1+zta), -(1+xi)*(1+zta),  (1+xi)*(1-eta), &
                                   (1+eta)*(1+zta),  (1+xi)*(1+zta),  (1+xi)*(1+eta), &
                                  -(1+eta)*(1+zta),  (1-xi)*(1+zta),  (1-xi)*(1+eta)/), &
                                shape(GradN))
        J       = matmul(GradN, Original)
        DetJ    = Det(J, 3)
        call InvMat3(J, InvMatJ, OK_Flag)
        if (OK_Flag .EQV. .FALSE.) STOP "***ERROR*** Derivative Of Shape Function Is SINGULAR"
        DerivN  = matmul(InvMatJ,GradN)
        Bx(:)   = DerivN(1,:)
        By(:)   = DerivN(2,:)
        Bz(:)   = DerivN(3,:)
        BMatrix = reshape((/((/Bx(i), 0D0, 0D0, By(i), 0D0, Bz(i), &
                             0D0, By(i), 0D0, Bx(i), Bz(i), 0D0, &
                             0D0, 0D0, Bz(i), 0D0, By(i), Bx(i)/), &
                             i = 1, ElementShapeNodes)/), Shape(BMatrix))
    end select
end subroutine HexB27

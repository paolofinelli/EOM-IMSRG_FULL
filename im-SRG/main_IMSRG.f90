program main_IMSRG
  use basic_IMSRG
  use HF_mod
  use IMSRG_ODE
  use IMSRG_MAGNUS
  use IMSRG_CANONICAL
  use operators
  use me2j_format
  ! ground state IMSRG calculation for nuclear system 
  implicit none
  
  type(spd) :: jbasis
  type(sq_op) :: HS,ETA,DH,w1,w2,Hcm,rirj,pipj,r2_rms
  type(cross_coupled_31_mat) :: CCHS,CCETA,WCC
  type(full_sp_block_mat) :: coefs,TDA,ppTDA,rrTDA
  character(200) :: inputs_from_command
  integer :: i,j,T,P,JT,a,b,c,d,g,q,ham_type,j3
  integer :: np,nh,nb,k,l,m,n,method_int,mi,mj,ma,mb
  real(8) :: hw ,sm,omp_get_wtime,t1,t2,bet_off,d6ji,gx,dcgi,dcgi00
  logical :: hartree_fock,tda_calculation,COM_calc,r2rms_calc,me2j,me2b
  external :: dHds_white_gs,dHds_TDA_shell,dHds_TDA_shell_w_1op
  external :: dHds_white_gs_with_1op,dHds_white_gs_with_2op
  external :: dHds_TDA_shell_w_2op
  integer :: heiko(30)
 

!============================================================
! READ INPUTS SET UP STORAGE STRUCTURE
!============================================================
 
  heiko = (/1,2,5,6,3,4,11,12,9,10,7,8,19,20,17,18,15,16,&
       13,14,29,30,27,28,25,26,23,24,21,22/) 
  
  call getarg(1,inputs_from_command) 
  call read_main_input_file(inputs_from_command,HS,ham_type,&
       hartree_fock,method_int,tda_calculation,COM_calc,r2rms_calc,me2j,&
       me2b,hw)
  
 
  HS%herm = 1
  HS%hospace = hw

  call read_sp_basis(jbasis,HS%Aprot,HS%Aneut)
  call allocate_blocks(jbasis,HS)   
  call print_header
  
  ! for calculating COM expectation value
  if (COM_calc) then  
     
     call duplicate_sq_op(HS,rirj)
     call duplicate_sq_op(HS,pipj)
     
     if (me2j) then  ! heiko format or scott format? 
        call read_me2j_interaction(HS,jbasis,ham_type,hw,rr=rirj,pp=pipj) 
     else
        call read_interaction(HS,jbasis,ham_type,hw,rr=rirj,pp=pipj)
     end if
     
     call calculate_h0_harm_osc(hw,jbasis,pipj,4)
     call calculate_h0_harm_osc(hw,jbasis,rirj,5)
 !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  else if (r2rms_calc) then ! radius of some sort 
  
     call duplicate_sq_op(HS,rirj)
     call duplicate_sq_op(HS,r2_rms) 
     
     if (me2j) then 
        call read_me2j_interaction(HS,jbasis,ham_type,hw,rr=rirj) 
     else
        call read_interaction(HS,jbasis,ham_type,hw,rr=rirj)
     end if
     
     call initialize_rms_radius(r2_rms,rirj,jbasis) 
 !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ 
  else    ! normal boring
  
     if (me2j) then 
        call read_me2j_interaction(HS,jbasis,ham_type,hw) 
     else if (me2b) then
        ! pre normal ordered interaction with three body included at No2b
        call read_me2b_interaction(HS,jbasis,ham_type,hw) 
        goto 12 ! skip the normal ordering. 
        ! it's already done
     else
        call read_interaction(HS,jbasis,ham_type,hw)
     end if
     
  end if
 
!============================================================
! BUILD BASIS
!============================================================
  call calculate_h0_harm_osc(hw,jbasis,HS,ham_type) 

  if (hartree_fock) then 
     
     if (COM_calc) then 
        call calc_HF(HS,jbasis,coefs,pipj,rirj)
        call normal_order(pipj,jbasis)
        call normal_order(rirj,jbasis)
     else if (r2rms_calc) then 
        call calc_HF(HS,jbasis,coefs,r2_rms)
        call normal_order(r2_rms,jbasis)
     else
        call calc_HF(HS,jbasis,coefs)
     end if 
    ! calc_HF normal orders the hamiltonian
  
  else 
     call normal_order(HS,jbasis) 
  end if

 
12  print*, HS%E0
  
call  print_matrix( HS%fhh )
call print_matrix( HS%mat(1)%gam(1)%X(1:10,1:10) ) 
  stop

!============================================================
! IM-SRG CALCULATION 
!============================================================ 
 
! just a large series of IF statements deciding exactly which type of
! calculation to run. (The call statements run the full calculation) 
  
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
! ground state decoupling
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  select case (method_int) 
  
  case (1) ! magnus 
    
     if (COM_calc) then 
        call magnus_decouple(HS,jbasis,pipj,rirj)
        call calculate_CM_energy(pipj,rirj,hw) 
     else if (r2rms_calc) then
        call magnus_decouple(HS,jbasis,r2_rms)
        call write_tilde_from_Rcm(r2_rms)
     else 
        call magnus_decouple(HS,jbasis) 
     end if 
     
  case (2) ! traditional
     if (COM_calc) then 
        call decouple_hamiltonian(HS,jbasis,dHds_white_gs_with_2op,pipj,rirj)
        call calculate_CM_energy(pipj,rirj,hw)  ! this writes to file
     else if (r2rms_calc) then 
        call decouple_hamiltonian(HS,jbasis,dHds_white_gs_with_1op,r2_rms)
!        call write_tilde_from_Rcm(r2_rms)
        print*, sqrt(r2_rms%E0)
    else 
        call decouple_hamiltonian(HS,jbasis,dHds_white_gs) 
    !    call discrete_decouple(HS,jbasis) 
     end if
     
  case (3) 
  
     if (COM_calc) then 
        call discrete_decouple(HS,jbasis,pipj,rirj)
        call calculate_CM_energy(pipj,rirj,hw)  ! this writes to file
     else if (r2rms_calc) then 
        call discrete_decouple(HS,jbasis,r2_rms)
        call write_tilde_from_Rcm(r2_rms)     
     else 
        call discrete_decouple(HS,jbasis) 
     end if

  case (4) ! magnus(2/3) 
    
     if (COM_calc) then 
        call magnus_decouple(HS,jbasis,pipj,rirj,quads='y')
        call calculate_CM_energy(pipj,rirj,hw) 
     else if (r2rms_calc) then
        call magnus_decouple(HS,jbasis,r2_rms,quads='y')
        call write_tilde_from_Rcm(r2_rms)
     else 
        call magnus_decouple(HS,jbasis,quads='y') 
     end if 
     
  case (5) ! magnus(2/3)[T] 
    
     if (COM_calc) then 
        call magnus_decouple(HS,jbasis,pipj,rirj,quads='y',trips='y')
        call calculate_CM_energy(pipj,rirj,hw) 
     else if (r2rms_calc) then
        call magnus_decouple(HS,jbasis,r2_rms,quads='y',trips='y')
        call write_tilde_from_Rcm(r2_rms)
     else 
        call magnus_decouple(HS,jbasis,quads='y',trips='y') 
     end if 

  case (6) ! magnus(2)[T] 
    
     if (COM_calc) then 
        call magnus_decouple(HS,jbasis,pipj,rirj,trips='y')
        call calculate_CM_energy(pipj,rirj,hw) 
     else if (r2rms_calc) then
        call magnus_decouple(HS,jbasis,r2_rms,trips='y')
        call write_tilde_from_Rcm(r2_rms)
     else 
        call magnus_decouple(HS,jbasis,trips='y') 
     end if 

  end select
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
! excited state decoupling
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  if (tda_calculation) then 
     
     call initialize_TDA(TDA,jbasis,HS%Jtarg,HS%Ptarg,HS%valcut)
     allocate(HS%exlabels(TDA%map(1),2))
     HS%exlabels=TDA%blkM(1)%labels
    
     select case (method_int) 
        case(1) !magnus
    
        if (COM_calc) then 
           call magnus_TDA(HS,TDA,jbasis,pipj,ppTDA,rirj,rrTDA) 
           call calculate_CM_energy_TDA(TDA,rirj,pipj,ppTDA,rrTDA,hw) 
        else if (r2rms_calc) then
           call magnus_TDA(HS,TDA,jbasis,r2_rms,rrTDA)
     !      print*, rrTDA%blkM(1)%eigval
        else 
           call magnus_TDA(HS,TDA,jbasis) 
        end if
        
        case(2) !traditional
     
        if (COM_calc) then 
           call TDA_decouple(HS,TDA,jbasis,dHds_TDA_shell_w_2op, &
                pipj,ppTDA,rirj,rrTDA) 
           call calculate_CM_energy_TDA(TDA,rirj,pipj,ppTDA,rrTDA,hw) 
        else if (r2rms_calc) then
           call TDA_decouple(HS,TDA,jbasis,dHds_TDA_shell_w_1op,&
                r2_rms,rrTDA)
           print*, rrTDA%blkM(1)%eigval
        else 
           call TDA_decouple(HS,TDA,jbasis,dHds_TDA_shell) 
        end if 
        
        case(3) !discrete
      
         
        if (COM_calc) then 
           call discrete_TDA(HS,TDA,jbasis,pipj,ppTDA,rirj,rrTDA) 
           call calculate_CM_energy_TDA(TDA,rirj,pipj,ppTDA,rrTDA,hw) 
        else if (r2rms_calc) then
           call discrete_TDA(HS,TDA,jbasis,r2_rms,rrTDA)
        else 
           call discrete_TDA(HS,TDA,jbasis) 
        end if 
        
        case(4) !magnus
    
        if (COM_calc) then 
           call magnus_TDA(HS,TDA,jbasis,pipj,ppTDA,rirj,rrTDA) 
           call calculate_CM_energy_TDA(TDA,rirj,pipj,ppTDA,rrTDA,hw) 
        else if (r2rms_calc) then
           call magnus_TDA(HS,TDA,jbasis,r2_rms,rrTDA)
     !      print*, rrTDA%blkM(1)%eigval
        else 
           call magnus_TDA(HS,TDA,jbasis) 
        end if
        
        case(5) !magnus
    
        if (COM_calc) then 
           call magnus_TDA(HS,TDA,jbasis,pipj,ppTDA,rirj,rrTDA) 
           call calculate_CM_energy_TDA(TDA,rirj,pipj,ppTDA,rrTDA,hw) 
        else if (r2rms_calc) then
           call magnus_TDA(HS,TDA,jbasis,r2_rms,rrTDA)
     !      print*, rrTDA%blkM(1)%eigval
        else 
           call magnus_TDA(HS,TDA,jbasis) 
        end if
        
        case(6) !magnus
    
        if (COM_calc) then 
           call magnus_TDA(HS,TDA,jbasis,pipj,ppTDA,rirj,rrTDA) 
           call calculate_CM_energy_TDA(TDA,rirj,pipj,ppTDA,rrTDA,hw) 
        else if (r2rms_calc) then
           call magnus_TDA(HS,TDA,jbasis,r2_rms,rrTDA)
     !      print*, rrTDA%blkM(1)%eigval
        else 
           call magnus_TDA(HS,TDA,jbasis) 
        end if
      
     end select
     
     
  end if 
  
end program main_IMSRG
!=========================================================================
subroutine print_header
  implicit none 
  
  print* 
  print*, 'Constructing Basis...' 
  print*
  print*, '=============================================================='
  print*, '  iter      s             E0        E0+MBPT(2)     |MBPT(2)|  '  
  print*, '=============================================================='

end subroutine   



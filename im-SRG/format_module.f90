module me2j_format
  use basic_IMSRG
  implicit none
  
  contains

subroutine get_me2j_spfile(eMaxchr)
  ! This constructs the sps file for
  ! me2j's format, after it's been converted to a pn-basis 
  implicit none 
  
  integer :: e,eMax,l,jj,tz,q,n
  character(2) :: eMaxchr
  character(13) :: fmt
  

  read(eMaxchr,'(I2)') eMax
  eMaxchr = adjustl(eMaxchr) 
  open(unit=24,file='../../sp_inputs/hk'//trim(eMaxchr)//'Lmax10.sps')
  
  q = 1
  
  fmt = '(5(I5),e17.7)'
  do  e = 0,eMax
     
     do l = mod(e,2),min(e,10),2
        
        n = (e-l)/2
  
        do jj = abs(2*l-1),2*l+1,2
           
           do tz = -1,1,2
              
              write(24,fmt) q, n , l , jj , tz, float(e) 
              q = q+1
           end do 
        end do 
     end do 
  end do 
  
  close(24) 
end subroutine


subroutine read_me2j_interaction(H,jbas,htype,hw,rr,pp) 
  use gzipmod
  implicit none 
  
  integer :: nlj1,nlj2,nnlj1,nnlj2,j,T,Mt,nljMax,endpoint,j_min,j_max,htype
  integer :: l1,l2,ll1,ll2,j1,j2,jj1,jj2,Ntot,i,q,bospairs,qx,ta,tb,tc,td
  integer :: eMax,iMax,jmax,jmin,JT,a,b,c,d,C1,C2,i1,i2,pre,COM,x,PAR,endsz
  integer,allocatable,dimension(:) :: indx 
  real(8),allocatable,dimension(:) :: ME,MEpp,MErr,me_fromfile,ppff,rrff
  real(8) :: V,g1,g2,g3,hw,pre2
  type(spd) :: jbas 
  type(sq_op) :: H
  type(sq_op),optional :: pp,rr
  logical :: pp_calc,rr_calc
  character(1) :: rem
  character(2) :: eMaxchr
  character(200) :: spfile,intfile,input,prefix
  character(200) :: itpath
  type(c_ptr) :: buf,buf2,buf3
  integer(c_int) :: hndle,hndle2,hndle3,sz,sz2,sz3,rx
  character(kind=C_CHAR,len=200) :: buffer,buffer2,buffer3
  common /files/ spfile,intfile,prefix 
  
  pp_calc=.false.
  rr_calc=.false.
  COM = 0
  
  if (present(pp)) pp_calc=.true.
  if (present(rr)) rr_calc=.true.
  if (htype == 1) COM = 1

  Ntot = jbas%total_orbits/2
  
  i = 0
  q = 0
  ! allocate array to store positions of matrix elements
  bospairs = bosonic_tp_index(Ntot,Ntot,Ntot) 
  allocate(indx(bospairs**2)) 
  indx = 0

  ! move in increments of two, because I use a pn basis,
  !  heiko's is isospin coupled (half the states) 

  eMax = maxval(jbas%e)   
  
  ! counting the states, and labeling them
  do nlj1=1, 2*Ntot,2 
     l1= jbas%ll(nlj1)
     j1= jbas%jj(nlj1)
     
     do nlj2 = 1, nlj1,2
        l2= jbas%ll(nlj2)
        j2= jbas%jj(nlj2)
        
       ! if (nint(jbas%e(nlj1) + jbas%e(nlj2)) > eMax )  exit
      
        do nnlj1 = 1 ,nlj1 , 2
           ll1= jbas%ll(nnlj1)
           jj1= jbas%jj(nnlj1)
           
           endpoint = nnlj1 
           if ( nlj1==nnlj1 ) endpoint = nlj2
         
           do nnlj2 = 1, endpoint , 2 
              ll2= jbas%ll(nnlj2)
              jj2= jbas%jj(nnlj2)
              
             ! if (nint(jbas%e(nlj1) + jbas%e(nlj2)) > eMax )  exit 
             
              if (mod(l1+l2,2) .ne. mod(ll1+ll2,2)) cycle
              jmin = max( abs(j1-j2) , abs(jj1-jj2) ) 
              jmax = min( j1+j2  , jj1+jj2) 
              
              if (jmin > jmax) cycle 
      
              indx(bosonic_tp_index((nlj2+1)/2,(nlj1+1)/2,Ntot)&
                   +bospairs*(bosonic_tp_index((nnlj2+1)/2,(nnlj1+1)/2,Ntot)-1)) = i+1 
        
              do JT = jmin,jmax,2
                 i = i + 4
              end do 
         
           
           end do
        end do 
     end do 
  end do 
  iMax = i 
  
  allocate(me(iMax)) 
  allocate(mepp(iMax))
  allocate(me_fromfile(10)) 
  allocate(ppff(10)) 
  if (rr_calc) then 
     allocate(rrff(10)) 
     allocate(merr(iMax)) 
  end if 
  

  write(eMaxchr,'(I2)') eMax 
  eMaxchr = adjustl(eMaxchr)  
  
  open(unit=34,file='../../inifiles/interactionpath')
  read(34,*) itpath 
  itpath = adjustl(itpath) 
  ! using zlib c library, which is bound with fortran in file "gzipmod.f90" 
  
  ! I don't know why you have to tack on those //achars(0) but it seems nessecary 
  hndle=gzOpen(trim(itpath)//trim(adjustl(intfile))//achar(0),"r"//achar(0)) 
  
 ! print*, trim(itpath)
  
  ! opening the pipj and rirj files 
  if (len(trim(eMaxchr)) == 1) then 
     hndle2=gzOpen(trim(itpath)//"tpp_eMax0"//trim(eMaxchr)//".me2j.gz"//achar(0),"r"//achar(0)) 
     if (rr_calc) then 
        hndle3=gzOpen(trim(itpath)//"r1r2_eMax0"//trim(eMaxchr)//".me2j.gz"//achar(0),"r"//achar(0)) 
     end if
  else
      hndle2=gzOpen(trim(itpath)//"tpp_eMax"//trim(eMaxchr)//".me2j.gz"//achar(0),"r"//achar(0)) 
     if (rr_calc) then 
        hndle3=gzOpen(trim(itpath)//"r1r2_eMax"//trim(eMaxchr)//".me2j.gz"//achar(0),"r"//achar(0)) 
     end if
  end if 
  
  
  sz=200;sz2=200;sz3=200 !c_ints, don't reuse them 
  
  buf=gzGets(hndle,buffer,sz) 
  buf2=gzGets(hndle2,buffer2,sz2)
  if (rr_calc) buf3=gzGets(hndle3,buffer3,sz3)
  
  endpoint = 10 
  write(rem,'(I1)') endpoint-1
  endsz = 130 
  
  do i = 1,iMax,10
  
     if (i+10 > iMax) then 
        deallocate(me_fromfile)
        deallocate(ppff) 
        allocate(me_fromfile( iMax - i + 1) ) 
        allocate(ppff(iMax-i + 1)) 
        if (rr_calc) then 
           deallocate(rrff)
           allocate(rrff(iMax-i + 1)) 
        end if 
        endpoint = iMax-i + 1
        endsz = 13+(endpoint-1)*13 
        write(rem,'(I1)') endpoint-1
     end if
  
     buf = gzGets(hndle,buffer(1:sz),sz)
     buf2 = gzGets(hndle2,buffer2(1:sz2),sz2)
     
  
     read(buffer(1:endsz),'(f12.7,'//rem//'(f13.7))') me_fromfile 
     read(buffer2(1:endsz),'(f12.7,'//rem//'(f13.7))') ppff 
   
     if (rr_calc) then 
        
        buf3 = gzGets(hndle3,buffer3(1:sz3),sz3)
        read(buffer3(1:endsz),'(f12.7,'//rem//'(f13.7))') rrff 
        
        do j = 1,endpoint 
           ME(i+j-1) = me_fromfile(j)
           MEpp(i+j-1) = ppff(j) 
           MErr(i+j-1) = rrff(j)
        end do
        
     else
        
        do j = 1,endpoint 
           ME(i+j-1) = me_fromfile(j)
           MEpp(i+j-1) = ppff(j) 
        end do
     end if 
  end do

  rx = gzClose(hndle) 
  rx = gzClose(hndle2)
  if(rr_calc) then 
     rx = gzClose(hndle3)
     deallocate(rrff)
     allocate(rrff(4))
  end if 
  
  deallocate(me_fromfile)
  deallocate(ppff)
  allocate(me_fromfile(4))
  allocate(ppff(4)) 
  
  ! redo this loop to put everything in pn basis
  
  i=0
  do nlj1=1, 2*Ntot,2 
     l1= jbas%ll(nlj1)
     j1= jbas%jj(nlj1)
     
     do nlj2 = 1, nlj1,2
        l2= jbas%ll(nlj2)
        j2= jbas%jj(nlj2)
         
        do nnlj1 = 1 ,nlj1 , 2
           ll1= jbas%ll(nnlj1)
           jj1= jbas%jj(nnlj1)
           
           endpoint = nnlj1 
           if ( nlj1==nnlj1 ) endpoint = nlj2
         
           do nnlj2 = 1, endpoint , 2 
              ll2= jbas%ll(nnlj2)
              jj2= jbas%jj(nnlj2)
                  
              if (mod(l1+l2,2) .ne. mod(ll1+ll2,2)) cycle
              jmin = max( abs(j1-j2) , abs(jj1-jj2) ) 
              jmax = min( j1+j2  , jj1+jj2) 
              PAR = mod(l1+l2,2) 
              if (jmin > jmax) cycle 
            
              do JT = jmin,jmax,2
                 me_fromfile=ME(i+1:i+4)
                 ppff = MEpp(i+1:i+4)
                 if (rr_calc) rrff = MErr(i+1:i+4)
                 i = i + 4 ! four different TMt qnums
 

 
!sum over all isospin configs
do a = nlj1,nlj1+1
   do b = nlj2,nlj2+1
      do c = nnlj1,nnlj1+1 
         do d = nnlj2,nnlj2+1  
           
            ! conversion factor to mT scheme 
            pre2 = 1.d0 
            if ( a == b ) pre2 = pre2*sqrt(0.5d0) 
            if ( c == d ) pre2 = pre2*sqrt(0.5d0) 
            
            ! heikos labeling is backwards
            ta = -jbas%itzp(a)
            tb = -jbas%itzp(b)
            tc = -jbas%itzp(c)
            td = -jbas%itzp(d)
            
            T = ta+tb
            if (tc+td .ne. T) cycle
            T = -T/2
            q = block_index(JT,T,Par)

            write(42,*) me_fromfile(1), me_fromfile(3) ,(nlj1+1)/2,(nlj2+1)/2,(nnlj1+1)/2,(nnlj2+1)/2,JT/2
     ! convert to pn matrix element       
     V =  0.125d0*(ta-tb)*(tc-td)*me_fromfile(1)+&   ! 00 clebsch
          kron_del(ta+tb,-2)*kron_del(tc+td,-2)*me_fromfile(2)+& ! 1-1 
          kron_del(ta+tb,2)*kron_del(tc+td,2)*me_fromfile(4)+& !11 
          0.125d0*abs((ta-tb)*(tc-td))*me_fromfile(3) !10 

     ! pipj 
     g3 = 0.125d0*(ta-tb)*(tc-td)*ppff(1)+&   ! 00 clebsch
          kron_del(ta+tb,-2)*kron_del(tc+td,-2)*ppff(2)+& ! 1-1 
          kron_del(ta+tb,2)*kron_del(tc+td,2)*ppff(4)+& !11 
          0.125d0*abs((ta-tb)*(tc-td))*ppff(3) !10 

     if (rr_calc) then 
        g2 = 0.125d0*(ta-tb)*(tc-td)*rrff(1)+&   ! 00 clebsch
          kron_del(ta+tb,-2)*kron_del(tc+td,-2)*rrff(2)+& ! 1-1 
          kron_del(ta+tb,2)*kron_del(tc+td,2)*rrff(4)+& !11 
          0.125d0*abs((ta-tb)*(tc-td))*rrff(3) !10 
     end if 
     
     ! getting rid of weird mass scaling 
     g3 = -2.d0*g3/hbarc2_over_mc2 

     ! center of mass subtraction
     V = (V - g3*COM*hw/(H%Aneut+H%Aprot)) *pre2 
    
     g3 = g3*pre2
     g2 = g2*pre2
     
     C1 = jbas%con(a)+jbas%con(b) + 1 !ph nature
     C2 = jbas%con(c)+jbas%con(d) + 1
    
     qx = C1*C2
     qx = qx + adjust_index(qx)   !Vpppp nature  

     ! get the indeces in the correct order
     pre = 1
     if ( a > b )  then 
        
        x = bosonic_tp_index(b,a,Ntot*2) 
        j_min = H%xmap(x)%Z(1)  
        i1 = H%xmap(x)%Z( (JT-j_min)/2 + 2) 
        pre = (-1)**( 1 + (jbas%jj(a) + jbas%jj(b) -JT)/2 ) 
     else
       ! if (a == b) pre = pre * sqrt( 2.d0 )
       
        x = bosonic_tp_index(a,b,Ntot*2) 
        j_min = H%xmap(x)%Z(1)  
        i1 = H%xmap(x)%Z( (JT-j_min)/2 + 2) 
     end if
  
     if (c > d)  then     
        
        x = bosonic_tp_index(d,c,Ntot*2) 
        j_min = H%xmap(x)%Z(1)  
        i2 = H%xmap(x)%Z( (JT-j_min)/2 + 2) 
        
        pre = pre * (-1)**( 1 + (jbas%jj(c) + jbas%jj(d) -JT)/2 ) 
     else 
       ! if (c == d) pre = pre * sqrt( 2.d0 )
      
        x = bosonic_tp_index(c,d,Ntot*2) 
        j_min = H%xmap(x)%Z(1)  
        i2 = H%xmap(x)%Z( (JT-j_min)/2 + 2) 
     end if

     ! kets/bras are pre-scaled by sqrt(2) if they 
     ! have two particles in the same sp-shell
        
     ! get the units right. I hope 
   
     
     if ((qx == 1) .or. (qx == 5) .or. (qx == 4)) then 
        H%mat(q)%gam(qx)%X(i2,i1)  = V *pre
        H%mat(q)%gam(qx)%X(i1,i2)  = V *pre
        
        if (rr_calc) then 
           rr%mat(q)%gam(qx)%X(i2,i1)  = hw*g2*pre/(H%Aneut + H%Aprot)
           rr%mat(q)%gam(qx)%X(i1,i2)  = hw*g2*pre/(H%Aneut + H%Aprot)
        end if 

        if (pp_calc) then 
           pp%mat(q)%gam(qx)%X(i2,i1)  = hw*g3*pre/(H%Aneut + H%Aprot)
           pp%mat(q)%gam(qx)%X(i1,i2)  = hw*g3*pre/(H%Aneut + H%Aprot)
        end if 

        
     else if (C1>C2) then
        H%mat(q)%gam(qx)%X(i2,i1)  = V *pre
        
        if (rr_calc) then 
           rr%mat(q)%gam(qx)%X(i2,i1)  = hw*g2*pre/(H%Aneut + H%Aprot) 
        end if
        
        if (pp_calc) then 
           pp%mat(q)%gam(qx)%X(i2,i1)  = hw*g3*pre/(H%Aneut + H%Aprot) 
        end if

     else
        H%mat(q)%gam(qx)%X(i1,i2) = V * pre
        
        if (rr_calc) then 
           rr%mat(q)%gam(qx)%X(i1,i2)  = hw*g2*pre/(H%Aneut + H%Aprot) 
        end if

        if (pp_calc) then 
           pp%mat(q)%gam(qx)%X(i1,i2)  = hw*g3*pre/(H%Aneut + H%Aprot) 
        end if

     end if 
     ! I shouldn't have to worry about hermiticity here, input is assumed to be hermitian
     
 end do;end do; end do; end do !end sums over isospin  
     
             end do ! end sum over j 
         
           
           end do  !end sums over Tcoupled lables
        end do 
     end do 
  end do   
 
end subroutine
!==========================================================
subroutine export_to_nushellX(H,jbas) 
  implicit none 
  
  type(sq_op) :: H
  type(spd) :: jbas
  integer :: i,j,k,l,J_tot,T_tot,Jx,Tx
  integer :: tot_pp_elems,tot_nn_elems,tot_pn_elems
  real(8) :: pre,mat_elem
  character(200) :: spfile,intfile,prefix 
  real(8),allocatable,dimension(:) :: sp_ens
  common /files/ spfile,intfile,prefix 
  

  open(unit=34,file='../../hamiltonians/'// &
       trim(adjustl(prefix))//'_nushell_1bd.sps') 

  write(34,'(A3)') 'iso' ! SHERPA only works for isospin coupled right now
  write(34,'(I2)') jbas%total_orbits/2 ! isospin coupled so devide by 2
  
  ! write .sps file
  do i = 1,jbas%total_orbits,2
     
     write(34,'(f10.1,2(f5.1),I3)') float(jbas%nn(i)),float(jbas%ll(i)), &
          float(jbas%jj(i))/2.0, 2 
     
  end do 
  close(34)
  
  
  open(unit=33,file='t1') ! pn 
  open(unit=34,file='t3') ! pp  
  open(unit=35,file='t4') ! nn
  
  tot_pn_elems = 0 
  tot_nn_elems = 0 
  tot_pp_elems = 0 
  
  do T_tot = 0,1
     do J_tot = 0,jbas%Jtotal_max
        
        
        do i = 1, jbas%total_orbits/2
           do j = i, jbas%total_orbits/2
              
              do k = 1, jbas%total_orbits/2
                 do l = k,jbas%total_orbits/2
                                      
                    pre = 1.d0 
                    if ( i == j)  pre = pre * .70710681186  
                    if ( k == l)  pre = pre * .70710681186 
                    
                    Jx = J_tot*2
                    Tx = T_tot*2
          
                    mat_elem = 0.5 * ( v_elem( 2*i-1 , 2*j , 2*k-1, 2*l , Jx,H,jbas ) + &
                         v_elem( 2*i , 2*j-1 , 2*k , 2*l-1 , Jx,H,jbas ) - (-1)**(T_tot) * &
                         ( v_elem( 2*i-1 , 2*j , 2*k , 2*l-1 , Jx,H,jbas ) +  &
                         v_elem( 2*i , 2*j-1 , 2*k-1 , 2*l , Jx,H,jbas ) ) ) !* pre**4
                     
                         mat_elem = mat_elem +0.5 * ( T_twobody( 2*i-1 , 2*j , 2*k-1,2*l , Jx,Tx,H,jbas ) + &
                              T_twobody( 2*i , 2*j-1 , 2*k,2*l-1 , Jx,Tx,H,jbas ) - (-1)**(T_tot) * &
                              ( T_twobody( 2*i-1 , 2*j , 2*k,2*l-1 , Jx,Tx,H,jbas ) +  &
                              T_twobody( 2*i , 2*j-1 , 2*k-1,2*l , Jx,Tx,H,jbas ) ) ) !* pre**4
                    
                    if (abs(mat_elem) > 1e-10) then 
                       write(33,'(4(I3),I5,I3,f15.7)') i,j,k,l,J_tot,T_tot,mat_elem
                       tot_pn_elems = tot_pn_elems + 1 
                    end if 
  
                    if (T_tot == 0)  cycle ! pp and nn terms are not included in T=0
                    
                    ! pp terms  Mt = -1
                    mat_elem = v_elem( 2*i-1 , 2*j-1 , 2*k-1, 2*l-1 , Jx,H,jbas )*pre
                     
                    if (abs(mat_elem) > 1e-10) then 
                       write(34,'(4(I3),I5,I3,f15.7)') i,j,k,l,J_tot,T_tot,mat_elem
                       tot_pp_elems = tot_pp_elems + 1 
                    end if 
                   
                    ! nn terms Mt = +1
                    mat_elem = v_elem( 2*i , 2*j , 2*k, 2*l , Jx,H,jbas )*pre
                   
                    if (abs(mat_elem) > 1e-10) then 
                       write(35,'(4(I3),I5,I3,f15.7)') i,j,k,l,J_tot,T_tot,mat_elem
                       tot_nn_elems = tot_nn_elems + 1 
                    end if 
                   
                    
                  end do 
               end do 
            end do 
         end do 
     end do 
  end do 
  close(33)
  close(34)
  close(35)
 
  allocate(sp_ens(jbas%total_orbits/2)) 
  do i = 1, jbas%total_orbits/2
     sp_ens(i) = T_elem(2*i,2*i,H,jbas)  
  end do
!=====write pn to file=======
  open(unit=33,file='t2') 
  write(33,*) tot_pn_elems, sp_ens,1.d0,1.d0,0.d0
  close(33) 
  
  call system('cat t2 t1 > '//'../../hamiltonians/'// &
       trim(adjustl(prefix))//'_nushell_TBME_Tz0.int && rm t1 && rm t2') 
!=====write pp to file=======
  open(unit=33,file='t2') 
  write(33,*) tot_pp_elems, sp_ens,1.d0,1.d0,0.d0
  close(33) 
  
  call system('cat t2 t3 > '//'../../hamiltonians/'// &
       trim(adjustl(prefix))//'_nushell_TBME_TzM.int && rm t3 && rm t2') 
!=====write nn to file=======
  open(unit=33,file='t2') 
  write(33,*) tot_nn_elems, sp_ens,1.d0,1.d0,0.d0
  close(33) 
  
  call system('cat t2 t4 > '//'../../hamiltonians/'// &
       trim(adjustl(prefix))//'_nushell_TBME_Tz1.int && rm t4 && rm t2') 
  
end subroutine

subroutine read_me2b_interaction(H,jbas,htype,hw,rr,pp) 
  use gzipmod
  implicit none 
  
  integer :: nlj1,nlj2,nnlj1,nnlj2,j,T,Mt,nljMax,endpoint,j_min,j_max,htype,Lmax
  integer :: l1,l2,ll1,ll2,j1,j2,jj1,jj2,Ntot,i,q,bospairs,qx,ta,tb,tc,td,bMax
  integer :: eMax,iMax,jmax,jmin,JT,a,b,c,d,C1,C2,i1,i2,pre,COM,x,PAR,endsz,aMax
  integer :: t1,t2,lj1,lj2,n1,n2,Pi,Tz,AA,BB,qq
  integer,allocatable,dimension(:) :: indx , nMax_lj
  real(8),allocatable,dimension(:) :: ME,MEpp,MErr,me_fromfile,ppff,rrff
  real(8) :: V,g1,g2,g3,hw,pre2
  type(spd) :: jbas 
  type(sq_op) :: H,stors
  type(sq_op),optional :: pp,rr
  logical :: pp_calc,rr_calc
  character(1) :: rem
  character(2) :: eMaxchr
  character(200) :: spfile,intfile,input,prefix
  character(200) :: itpath
  integer :: lj,twol,twoj,ljMax,idx,idxx
  integer,allocatable,dimension(:,:) :: SPBljs 
  type(c_ptr) :: buf,buf2,buf3
  integer(c_int) :: hndle,hndle2,hndle3,sz,sz2,sz3,rx
  character(kind=C_CHAR,len=200) :: buffer,buffer2,buffer3
  common /files/ spfile,intfile,prefix 
  
  rr_calc = .false.
  pp_calc = .false. 
  
  Lmax = 10
  eMax = 14
! populate lj array
  lj = 0
  do twol = 0, 2 * Lmax , 2
     do  twoj = abs(twol - 1) , twol+1 , 2
        lj=lj+1
     end do 
  end do 
  ljMax = lj 
  allocate(SPBljs(lj,2)) 
  allocate(nMax_lj(lj))
  
  lj = 0
  do twol = 0, 2 * Lmax , 2
     do  twoj = abs(twol - 1) , twol+1 , 2
        lj=lj+1
        SPBljs(lj,1) = twol
        sPBljs(lj,2) = twoj
        nMax_lj(lj) = (eMax - twol/2)/2
     end do
  end do
  
  allocate(stors%mat(H%nblocks))
  
  hndle=gzOpen('O16_chi2b3bjs_lec04_srg0625_eMax14_lMax10_hwHO020.ham0.me2b.gz'//achar(0),"r"//achar(0)) 
  
  sz=200
  
  buf=gzGets(hndle,buffer,sz) 
  buf=gzGets(hndle,buffer,sz) 
  buf=gzGets(hndle,buffer,sz) 
  
  read(buffer(6:8),'(I3)') bMax
  if (bMax+1 .ne. H%nblocks) print*, 'fuck, diff num of blcks' , bMax, H%nblocks
  
sz = 20
 q = 0
! heiko's code calls protons 1 and neutrons 0

do Tz = 1 , -1, -1  
  do Pi = 0,1
     do JT = 0, 2*jbas%Jtotal_max,2 
        if ((JT == 2*jbas%Jtotal_max) .and. (Pi==1)) cycle
        q = q+1
     
      buf=gzGets(hndle,buffer,sz) 
     
  
      read(buffer(10:16),'(I6)') aMax 
  
      stors%mat(q)%npp = aMax + 1 ! don't worry about pp, hh, ph for this
      
      ! this is the map from heiko's "a" to my two sp labels
  
      allocate(stors%mat(q)%qn(1)%Y( aMax+1, 2) ) 
  
      stors%mat(q)%lam(1) = JT
      stors%mat(q)%lam(2) = Pi
      stors%mat(q)%lam(3) = Tz
      
      select case ( Tz)
         case ( -1 ) 
            t1 = -1
            t2 = -1
         case ( 0 ) 
            t1 = -1 
            t2 = 1
         case ( 1 ) 
            t1 = 1
            t2 = 1
         case default 
            print*, 'son of a fuck.' 
      end select
                 
      a = 0
     
      do lj1 = 1, ljMax
        do lj2 = 1, ljMax

           j1 = SPBljs(lj1,2) 
           j2 = SPBljs(lj2,2)
           l1 = SPBljs(lj1,1)/2
           l2 = SPBljs(lj2,1)/2
           
           if ( ( JT < abs(j1-j2) ) .or. (JT > j1 + j2) ) cycle
           if ( mod(l1 + l2 ,2 ) .ne.Pi ) cycle 


           do n1 = 0,nMax_lj(lj1)
              idx = (lj1-1) * (nMax_lj(1) +1 ) +n1 
              do n2 = 0,nMax_lj(lj2) 
                 idxx = (lj2-1) * (nMax_lj(1) +1 ) +n2                 
                 
                  if ( (Tz .ne. 0) .and. (idx > idxx) ) cycle
                  if ( (mod(JT/2,2) == 1) .and. (lj1==lj2) .and. &
                       (n1==n2) .and. (Tz .ne. 0) ) cycle
                  
                  ! now search for sp labels
                  do i = 1, jbas%total_orbits 
                     if ( jbas%jj(i) .ne. j1 ) cycle
                     if ( jbas%nn(i) .ne. n1 ) cycle
                     if ( jbas%ll(i) .ne. l1 ) cycle
                     if ( jbas%itzp(i) .ne. t1 ) cycle                     
                     exit
                  end do 
                  
                  do j = 1, jbas%total_orbits 
                     if ( jbas%jj(j) .ne. j2 ) cycle
                     if ( jbas%nn(j) .ne. n2 ) cycle
                     if ( jbas%ll(j) .ne. l2 ) cycle
                     if ( jbas%itzp(j) .ne. t2 ) cycle                     
                     exit
                  end do 
                  
                  a = a + 1
                !  print*, a, i ,j 
                 ! stop
                 stors%mat(q)%qn(1)%Y(a,1) = i
                 stors%mat(q)%qn(1)%Y(a,2) = j

               end do
            end do
         end do
      end do
      
    
      if ( a .ne. aMax+1 ) print*, 'douche',q, a, aMax,JT,Pi,Tz
    
   end do
end do 
end do 



! okay for now on there is a space, then a line that specifies the block
! and aMax for the block. We already know that stuff so we will just ignore
! it and read in the matrix elements
sz = 21
qq = 0
do Tz = 1 , -1, -1  
  do Pi = 0,1
     do JT = 0, 2*jbas%Jtotal_max,2 
        if ((JT == 2*jbas%Jtotal_max) .and. (Pi==1)) cycle
        qq = qq+1 ! heikos block index
     
        q = block_index(JT,Tz,Pi) ! my block index
        
        ! space then label
      buf=gzGets(hndle,buffer,sz) 
      buf=gzGets(hndle,buffer,sz)
        ! ignore
      sz = 30
      
      
      do AA = 1, stors%mat(qq)%npp 
         do BB = AA , stors%mat(qq)%npp 
            
      buf=gzGets(hndle,buffer,sz)
         ! figure out where the spaces are that separate things 
      i = 1
      ! first space
      do 
         if ( buffer(i:i) == ' ' ) then
            i = i + 2
            exit
         end if
         i = i + 1
      end do
      ! second space
      do 
         if ( buffer(i:i) == ' ' ) then 
            i = i + 2
            exit
         end if
         i = i + 1
      end do
      ! okay now i should be the position of the first 
      ! character of the TBME for the labels a <= b
      
      if ( buffer(i:i) == '-' ) then 
         ! negative number
         read(buffer(i:i+10), '( f11.8 )' )  V 
      else 
         ! positive
         read(buffer(i:i+9), '( f10.8 )' )  V 
      end if 
      
      
      
      ! oTay should have the matrix element now. 
     
      ! indeces     
      a = stors%mat(qq)%qn(1)%Y(AA,1)
      b = stors%mat(qq)%qn(1)%Y(AA,2)      
      c = stors%mat(qq)%qn(1)%Y(BB,1)
      d = stors%mat(qq)%qn(1)%Y(BB,2)      
       
      ! i think the scaling and COM subtraction have already been done
      ! I HOpe. 

!=========================================================================
      ! start the classical method of sorting these into my arrays now
!=========================================================================     
     C1 = jbas%con(a)+jbas%con(b) + 1 !ph nature
     C2 = jbas%con(c)+jbas%con(d) + 1
    
     qx = C1*C2
     qx = qx + adjust_index(qx)   !Vpppp nature  

     ! get the indeces in the correct order
     pre = 1
     if ( a > b )  then 
        
        x = bosonic_tp_index(b,a,Ntot) 
        j_min = H%xmap(x)%Z(1)  
        i1 = H%xmap(x)%Z( (JT-j_min)/2 + 2) 
        pre = (-1)**( 1 + (jbas%jj(a) + jbas%jj(b) -JT)/2 ) 
     else
       ! if (a == b) pre = pre * sqrt( 2.d0 )
       
        x = bosonic_tp_index(a,b,Ntot) 
       
        j_min = H%xmap(x)%Z(1)  
        i1 = H%xmap(x)%Z( (JT-j_min)/2 + 2) 
     end if
  
     if (c > d)  then     
        
        x = bosonic_tp_index(d,c,Ntot) 
        j_min = H%xmap(x)%Z(1)  
        i2 = H%xmap(x)%Z( (JT-j_min)/2 + 2) 
        
        pre = pre * (-1)**( 1 + (jbas%jj(c) + jbas%jj(d) -JT)/2 ) 
     else 
       ! if (c == d) pre = pre * sqrt( 2.d0 )
      
        x = bosonic_tp_index(c,d,Ntot) 
        j_min = H%xmap(x)%Z(1)  
        i2 = H%xmap(x)%Z( (JT-j_min)/2 + 2) 
     end if

     ! kets/bras are pre-scaled by sqrt(2) if they 
     ! have two particles in the same sp-shell
        
     ! get the units right. I hope 
 
     
     if ((qx == 1) .or. (qx == 5) .or. (qx == 4)) then 
        H%mat(q)%gam(qx)%X(i2,i1)  = V *pre
        H%mat(q)%gam(qx)%X(i1,i2)  = V *pre
        
        if (rr_calc) then 
           STOP 'fuck, this is not implemented yet' 
           rr%mat(q)%gam(qx)%X(i2,i1)  = hw*g2*pre/(H%Aneut + H%Aprot)
           rr%mat(q)%gam(qx)%X(i1,i2)  = hw*g2*pre/(H%Aneut + H%Aprot)
        end if 

        if (pp_calc) then 
           STOP 'fuck, this is not implemented yet' 
           pp%mat(q)%gam(qx)%X(i2,i1)  = hw*g3*pre/(H%Aneut + H%Aprot)
           pp%mat(q)%gam(qx)%X(i1,i2)  = hw*g3*pre/(H%Aneut + H%Aprot)
        end if 

        
     else if (C1>C2) then
        H%mat(q)%gam(qx)%X(i2,i1)  = V *pre
        
        if (rr_calc) then 
           STOP 'fuck, this is not implemented yet' 
           rr%mat(q)%gam(qx)%X(i2,i1)  = hw*g2*pre/(H%Aneut + H%Aprot) 
        end if
        
        if (pp_calc) then 
           STOP 'fuck, this is not implemented yet' 
           pp%mat(q)%gam(qx)%X(i2,i1)  = hw*g3*pre/(H%Aneut + H%Aprot) 
        end if

     else
        H%mat(q)%gam(qx)%X(i1,i2) = V * pre
        
        if (rr_calc) then 
           STOP 'fuck, this is not implemented yet' 
           rr%mat(q)%gam(qx)%X(i1,i2)  = hw*g2*pre/(H%Aneut + H%Aprot) 
        end if

        if (pp_calc) then 
           STOP 'fuck, this is not implemented yet' 
           pp%mat(q)%gam(qx)%X(i1,i2)  = hw*g3*pre/(H%Aneut + H%Aprot) 
        end if

     end if 
     ! I shouldn't have to worry about hermiticity here, input is assumed to be hermitian

   
        end do ! end loop over BB
     end do  ! end loop over AA
     
     
      end do   ! end loops over conserved quantities
   end do 
end do 
         
      
! i guess we are done 
rx = gzClose(hndle)

end subroutine
!==========================================================

  
end module



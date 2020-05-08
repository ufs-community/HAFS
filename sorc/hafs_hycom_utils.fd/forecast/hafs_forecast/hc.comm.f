      MODULE OC_cc

      USE CMP_COMM, ONLY:

     >   MPI_COMM_Ocean => COMM_local,

     >   Coupler_id,
     >   component_master_rank_local,
     >   process_rank_local,
     >   component_nprocs,
     >   ibuffer,

     >   MPI_INTEGER,MPI_STATUS_SIZE,

     >   kind_REAL,kind_alt_REAL,MPI_kind_REAL,MPI_kind_alt_REAL

      implicit none

      real (kind=kind_REAL) dtc            !<- Coupling period

      integer i_dtc2dto /100/,  !<- Coupling period / OM time step
     >        n_ts /-1/   !<- number of time step - 1
                          ! (increments/used in OC_SENDSST)

      integer imt,jmt,NX,NY,NLEV,nt,NGP,NGPsub,rc

      integer i_f,j_f,i_l,j_l

      integer ifc_g,jfc_g,ilc_g,jlc_g

      integer, parameter:: kind_sfcflux=kind_REAL,
     >                     kind_SST=kind_REAL,
     >                     kind_SLM=kind_REAL
      integer MPI_DATATYPE_sfcflux
      integer MPI_DATATYPE_SST 
      integer MPI_DATATYPE_SLM

      integer, parameter :: nc=1  ! # of copies of each flux

      real,allocatable:: ALONt(:,:),ALATt(:,:),
     >                   ALONu(:,:),ALATu(:,:),
     >                   ALONv(:,:),ALATv(:,:)

c     real(kind=kind_SLM),allocatable:: SLMt(:,:),SLMu(:,:),SLMv(:,:)
!<- these are not needed other than for printout purposes. Uncomment
!if the latter require (note same indication elsewhere)

Controls:
      integer nunit_announce /6/, VerbLev /3/
      integer Waves_id /-10/
C To control awo couplings
      integer ia2o /1/,
     >        ia2w /1/,
     >        io2a /2/,
     >        io2w /2/,
     >        iw2a /1/,
     >        iw2o /2/      ! [0/1/2] 1 for dTau; 2 for Stokes Drift

      SAVE

      END MODULE OC_cc
C
C***********************************************************************
C
      MODULE SFLUX_cc

      USE OC_cc, ONLY: kind_sfcflux

      implicit none

      integer num_sflx /8/  ! # of surf. fluxes to be dealt with

      real(kind=kind_sfcflux),allocatable:: sflx(:,:,:)

      real missing_value_flag /-1.E30/ ! see subr-s OC_INIT, OC_RECV_SBC

      SAVE

      END MODULE SFLUX_cc


C
C***********************************************************************
c<-hsk 2/17/2016: for wave coupling
c Modified by hsk 9/26/2018.
c 
      MODULE WW3_cc

      USE OC_cc, ONLY: kind_REAL

      IMPLICIT NONE

      integer num_sd /3/    ! # of binned Stokes Drift components
      integer num_sc /2/    ! (x,y)-components of Stokes Drift/Dtau

      real too_low /-1.E20/ ! for WW3 

      integer, parameter:: kind_curr=kind_REAL,
     >         kind_length=kind_REAL,
     >         kind_stress=kind_REAL

      integer MPI_DATATYPE_cur,
     >        MPI_DATATYPE_length,
     >        MPI_DATATYPE_stress

c---------------------------------------------------
c    local dummay variables: 
c
c--- send by HYCOM - after assemble in (NX by NY)
      real(kind=kind_curr),allocatable::
     >     SSCX(:,:), SSCY(:,:),  ! sea surface currents, done by HSK 2/17/2016
     >     DPCX(:,:), DPCY(:,:)   ! deep currents

c--- receved by HYCOM - before disassemble in (NX by NY)
      real(kind=kind_stress), allocatable::
     >     DTXG(:,:), DTYG(:,:),  ! wind stress modified by wave stress w/ 2-components
     >     dtxc(:,:), dtyc(:,:),  ! -> after disassemble
     >     STDX(:,:), STDY(:,:),    ! surface mean Stokes Drift in (NX by NY)
     >     xstk(:,:), ystk(:,:),    ! -> after diassemble
     >     STDX3(:,:,:), STDY3(:,:,:),    ! (future use) a set of 3 partitioned Stokes Drifts
     >     xstk3(:,:,:), ystk3(:,:,:)   ! -> after disassemble of (STDX3,STDY3)

      real(kind=kind_length),allocatable::
     >     AVGWL(:,:), ! mean wavelength corresponding to surface Stokes Drift
     >     mnwl(:,:),  ! -> after disassemble
     >     P3WL(:,:,:),   ! wavelength reserved for (num_sd=1,3) partitioned Stokes Drift
     >     wl3b(:,:,:),    ! -> after disassembl
     >     KPPML(:,:)  ! tiled surface boundary layer depth

      real(kind=kind_curr),allocatable::
     >     WBC(:,:),      ! vertical velocity at the wave-air-sea interface before disassemble
     >     bcondw(:,:)    ! after disassemble

      SAVE

      END MODULE WW3_cc
c->hsk.
c
C
C***********************************************************************
C
      SUBROUTINE OC_CMP_START

c     USE OC_cc, ONLY: process_rank_local,VerbLev,ibuffer,Coupler_id
      USE OC_cc

      implicit none

      integer Ocean_id /2/, Ocean_master_rank_local /0/, Ocean_spec/2/
      integer ibuf(1)
      integer ierr
      character*20 s
C

                      !<-id of OM as a component of the coupled system
      call CMP_INIT(Ocean_id,1)
                             !<-"flexibility level"
      if (Coupler_id.ge.0) VerbLev=min(VerbLev,ibuffer(4))

c     if (process_rank_local.eq.Ocean_master_rank_local) then
c       print*,'**OM: back from CMP_INIT, to call CMP_INTRO'
c     end if

      call CMP_INTRO(Ocean_master_rank_local)

      write(s,'(i2)') VerbLev
      call OC_ANNOUNCE('back from CMP_INTRO, VerbLev='//s,2)

      ibuf(1)=Ocean_spec

      call CMP_INTEGER_SEND(ibuf,1)

      write(s,'(i2)') ibuf(1)
      call OC_ANNOUNCE('OC_CMP_START: returning, sent Ocean_spec='//s,2)

      call CMP_gnr_RECV(Waves_id,1,MPI_INTEGER)
      write(s,'(i4)') Waves_id
      call OC_ANNOUNCE('back from CMP_INTEGER_RECV, WM id is '//s,2)
      call MPI_BCAST(Waves_id,1,MPI_INTEGER,
     >  component_master_rank_local,MPI_COMM_Ocean,ierr)
      call OC_ANNOUNCE('OC_CMP_START: Waves_id broadcast',2)

      call CMP_gnr_RECV(ia2o,1,MPI_INTEGER)
      write(s,'(i4)') ia2o
      call OC_ANNOUNCE('back from CMP_INTEGER_RECV, ia2o is '//s,2)
      call MPI_BCAST(ia2o,1,MPI_INTEGER,
     >  component_master_rank_local,MPI_COMM_Ocean,ierr)
      call OC_ANNOUNCE('ATM_CMP_START: ia2o broadcast',2)

      call CMP_gnr_RECV(io2a,1,MPI_INTEGER)
      write(s,'(i4)') io2a
      call OC_ANNOUNCE('back from CMP_INTEGER_RECV, io2a is '//s,2)
      call MPI_BCAST(io2a,1,MPI_INTEGER,
     >  component_master_rank_local,MPI_COMM_Ocean,ierr)
      call OC_ANNOUNCE('ATM_CMP_START: io2a broadcast',2)

      call CMP_gnr_RECV(io2w,1,MPI_INTEGER)
      write(s,'(i4)') io2w
      call OC_ANNOUNCE('back from CMP_INTEGER_RECV, io2w is '//s,2)
      call MPI_BCAST(io2w,1,MPI_INTEGER,
     >  component_master_rank_local,MPI_COMM_Ocean,ierr)
      call OC_ANNOUNCE('ATM_CMP_START: io2w broadcast',2)

      call CMP_gnr_RECV(iw2o,1,MPI_INTEGER)
      write(s,'(i4)') iw2o
      call OC_ANNOUNCE('back from CMP_INTEGER_RECV, iw2o is '//s,2)
      call MPI_BCAST(iw2o,1,MPI_INTEGER,
     >  component_master_rank_local,MPI_COMM_Ocean,ierr)
      call OC_ANNOUNCE('ATM_CMP_START: iw2o broadcast',2)

      return
      END
C
C***********************************************************************
C
      SUBROUTINE OC_INIT(imt_,jmt_,km_, i_f_, i_l_, j_f_,    j_l_,
                           !<-"total"     !<-"first"           !<-"last"
     >ifc_g_,ilc_g_,jfc_g_,jlc_g_,missing_value_flag_)
        !<-"comp."      !<-"global"
                     ! i_f_, i_l_, j_f_, j_l_ are local in tile
      USE OC_cc
      USE SFLUX_cc
      USE WW3_cc
c
      implicit none

      integer imt_,jmt_,km_,i_f_,i_l_,j_f_,j_l_,
     >ifc_g_,jfc_g_,ilc_g_,jlc_g_

      real missing_value_flag_
C
      call OC_ANNOUNCE('OC_INIT: entered',2)

      imt=imt_
      jmt=jmt_
      NX=imt_
      NY=jmt_
      NLEV=km_

      i_f=i_f_
      i_l=i_l_
      j_f=j_f_
      j_l=j_l_

      ifc_g=ifc_g_
      jfc_g=jfc_g_
      ilc_g=ilc_g_
      jlc_g=jlc_g_

      NGPsub=(i_l-i_f+1)*(j_l-j_f+1)

      NGP=NY*NX

c     if(process_rank_local.eq.component_master_rank_local) then
        allocate(ALONt(NX,NY),ALATt(NX,NY),
     >  ALONu(NX,NY),ALATu(NX,NY),
     >  ALONv(NX,NY),ALATv(NX,NY))

c
c       allocate(SLMt(NX,NY),
c    >  SLMu(NX,NY),SLMv(NX,NY))
!<- these are not needed other than for printout purposes. Uncomment
!if the latter require (note same indication elsewhere)
c     end if
!<- if/endif commented out in case assembling/dissasembling routines
! somehow need these arrays allocated for all processes

      allocate(sflx(i_f:i_l,j_f:j_l,num_sflx))

c<-hsk: local dummay vars. for wave coupling
      allocate(SSCX(NX,NY),SSCY(NX,NY),
     >         DPCX(NX,NY),DPCY(NX,NY))

      allocate(DTXG(NX,NY),DTYG(NX,NY))
      allocate(dtxc(i_f:i_l,j_f:j_l),
     >         dtyc(i_f:i_l,j_f:j_l))

      allocate(STDX(NX,NY),STDY(NX,NY))
      allocate(xstk(i_f:i_l,j_f:j_l),
     >         ystk(i_f:i_l,j_f:j_l))

      allocate(AVGWL(NX,NY))
      allocate(mnwl(i_f:i_l,j_f:j_l))

      allocate(STDX3(NX,NY,num_sd),STDY3(NX,NY,num_sd))
      allocate(xstk3(i_f:i_l,j_f:j_l,num_sd),
     >         ystk3(i_f:i_l,j_f:j_l,num_sd))

      allocate(P3WL(NX,NY,num_sd))
      allocate(wl3b(i_f:i_l,j_f:j_l,num_sd))

      allocate(WBC(NX,NY))
      allocate(bcondw(i_f:i_l,j_f:j_l))

      allocate(KPPML(NX,NY))

c->hsk
c
      if (kind_sfcflux.eq.kind_REAL) then
        MPI_DATATYPE_sfcflux=MPI_kind_REAL
      else if (kind_sfcflux.eq.kind_alt_REAL) then
        MPI_DATATYPE_sfcflux=MPI_kind_alt_REAL
      else
        call GLOB_ABORT(1,
     >  'kind_sfcflux is neither kind_REAL nor kind_alt_REAL',1)
      end if

      missing_value_flag_=missing_value_flag

      if (kind_SST.eq.kind_REAL) then
        MPI_DATATYPE_SST=MPI_kind_REAL
      else if (kind_SST.eq.kind_alt_REAL) then
        MPI_DATATYPE_SST=MPI_kind_alt_REAL
      else
        call GLOB_ABORT(1,
     >  'kind_SST is neither kind_REAL nor kind_alt_REAL',1)
      end if
      if (kind_SLM.eq.kind_REAL) then
        MPI_DATATYPE_SLM=MPI_kind_REAL
      else if (kind_SLM.eq.kind_alt_REAL) then
        MPI_DATATYPE_SLM=MPI_kind_alt_REAL
      else
        call GLOB_ABORT(1,
     >  'kind_SLM is neither kind_REAL nor kind_alt_REAL',1)
      end if
c
c - wave coupling
c
      if (kind_curr.eq.kind_REAL) then
        MPI_DATATYPE_cur=MPI_kind_REAL
      else if (kind_curr.eq.kind_alt_REAL) then
        MPI_DATATYPE_cur=MPI_kind_alt_REAL
      else
        call GLOB_ABORT(1,
     >  'kind_currr is neither kind_REAL nor kind_alt_REAL',1)
      end if
c
      if (kind_stress.eq.kind_REAL) then
        MPI_DATATYPE_stress=MPI_kind_REAL
      else if (kind_stress.eq.kind_alt_REAL) then
        MPI_DATATYPE_stress=MPI_kind_alt_REAL
      else
        call GLOB_ABORT(1,
     >  'kind_stress is neither kind_REAL nor kind_alt_REAL',1)
      end if
c
      if (kind_length.eq.kind_REAL) then
        MPI_DATATYPE_length=MPI_kind_REAL
      else if (kind_length.eq.kind_alt_REAL) then
        MPI_DATATYPE_length=MPI_kind_alt_REAL
      else
        call GLOB_ABORT(1,
     >  'kind_length is neither kind_REAL nor kind_alt_REAL',1)
      end if
c
      if (VerbLev.ge.3) print*,'OC_INIT: returning ',
     >imt_,jmt_,km_,i_f_,i_l_,j_f_,j_l_,ifc_g_,ilc_g_,jfc_g_,jlc_g_

      return
      END
C
C***********************************************************************
C
      SUBROUTINE OC_SENDGRIDS(xt,yt,xu,yu,xv,yv,dt)

      USE OC_cc

      implicit none

      real(kind=kind_REAL), dimension(i_f:i_l,j_f:j_l) ::
     >     xt,yt,xu,yu,xv,yv
      real(kind=kind_REAL) dt
      
      integer ibuf(2)
      real buf(1)
      character*20 s
C

      if (Coupler_id.lt.0) return    !   <- standalone mode

      buf(1)=dt   ! <- OM time step
      write(s,'(1pe20.12)') dt
      call OC_ANNOUNCE('(BP) to send time step='//s,2)
      call CMP_SEND(buf,1)
      call OC_ANNOUNCE('(BP) time step='//s//' sent',1)

      IF (component_master_rank_local.eq.process_rank_local) THEN

        call CMP_RECV(buf,1)
        dtc=buf(1)
        write(s,'(1pe20.12)') dtc
        call OC_ANNOUNCE('time received: '//s,1)
        i_dtc2dto=nint(dtc/dt)
        if (abs(i_dtc2dto-dtc/dt).gt.1.E-7) call GLOB_ABORT(1,
     >  'OM: ABORTED: dtc is not a multiple of dt',1)

        ibuf(1)=NX
        ibuf(2)=NY
        call OC_ANNOUNCE('to send grid dimensions',2)
        call CMP_INTEGER_SEND(ibuf,2)
        call OC_ANNOUNCE('grid dimensions sent',1)

        ibuf(1)=i_dtc2dto

           print*,'xu(1:3,1:3): '
           print*,xu(1:3,1:3)
           print*,'yu(1:3,1:3): '
           print*,yu(1:3,1:3)

      END IF

      call MPI_BCAST(ibuf,1,MPI_INTEGER,component_master_rank_local,
     >MPI_COMM_Ocean,rc)
      i_dtc2dto=ibuf(1)

      call OC_ANNOUNCE('(BP) i_dtc2dto broadcast OK',2)

      call ASSEMBLE_cc(ALONt,xt)
      call ASSEMBLE_cc(ALATt,yt)
      call ASSEMBLE_cc(ALONu,xu)
      call ASSEMBLE_cc(ALATu,yu)
      call ASSEMBLE_cc(ALONv,xv)
      call ASSEMBLE_cc(ALATv,yv)

         IF (component_master_rank_local.eq.process_rank_local) THEN
           print*,'xu(1:3,1:3): '
           print*,xu(1:3,1:3)
           print*,'yu(1:3,1:3): '
           print*,yu(1:3,1:3)

           print*,'ALONu(1:3,1:3): '
           print*,ALONu(1:3,1:3)
           print*,'ALATu(1:3,1:3): '
           print*,ALATu(1:3,1:3)
         END IF


      call OC_ANNOUNCE('(BP) to send grid arrays (6 MPI calls)',2)

      print*,"before CMP_SEND(Alont"
      call CMP_SEND(ALONt,NGP)
      print*,"before CMP_SEND(Alont"
      call CMP_SEND(ALATt,NGP)
      call CMP_SEND(ALONu,NGP)
      call CMP_SEND(ALATu,NGP)
      call CMP_SEND(ALONv,NGP)
      call CMP_SEND(ALATv,NGP)

      call OC_ANNOUNCE('the 6 grid arrays sent',1)

      call OC_ANNOUNCE('(BP) OC_SENDGRIDS: returning',2)

      return
      END

C
C***********************************************************************
C  hsk 2018: To avoid send assembled plon/lat,ulon/lat and vlon/lat 
C            to a coupler for interpolation.
C
      SUBROUTINE OC_RDnSENDGRIDS(dt)

      USE OC_cc

      implicit none

      real*4,allocatable:: axt(:,:),ayt(:,:),
     >                     axu(:,:),ayu(:,:),
     >                     axv(:,:),ayv(:,:)

      real(kind=kind_REAL) dt

      integer ibuf(2)
      real buf(1)
      character*20 s
C
      if (Coupler_id.lt.0) return    !   <- standalone mode

      buf(1)=dt   ! <- OM time step
      write(s,'(1pe20.12)') dt
      call OC_ANNOUNCE('(BP) to send time step='//s,2)
      call CMP_SEND(buf,1)
      call OC_ANNOUNCE('(BP) time step='//s//' sent',1)

      IF (component_master_rank_local.eq.process_rank_local) THEN

        call CMP_RECV(buf,1)
        dtc=buf(1)
        write(s,'(1pe20.12)') dtc
        call OC_ANNOUNCE('time received: '//s,1)
        i_dtc2dto=nint(dtc/dt)
        if (abs(i_dtc2dto-dtc/dt).gt.1.E-7) call GLOB_ABORT(1,
     >  'OM: ABORTED: dtc is not a multiple of dt',1)

        ibuf(1)=NX
        ibuf(2)=NY
        call OC_ANNOUNCE('to send grid dimensions',2)
        call CMP_INTEGER_SEND(ibuf,2)
        call OC_ANNOUNCE('grid dimensions sent',1)

        ibuf(1)=i_dtc2dto

      END IF

      call MPI_BCAST(ibuf,1,MPI_INTEGER,component_master_rank_local,
     >MPI_COMM_Ocean,rc)
      i_dtc2dto=ibuf(1)

      call OC_ANNOUNCE('(BP) i_dtc2dto broadcast OK',2)

C<-hsk 2018: to avoid send vland (-1E+30)
C
C --- read in a hycom grid file,
C     send to a coupler

      IF (component_master_rank_local.eq.process_rank_local) THEN
        allocate(axt(NX,NY),ayt(NX,NY),
     >           axu(NX,NY),ayu(NX,NY),
     >           axv(NX,NY),ayv(NX,NY))
           call rdgrids(axt,ayt,axu,ayu,axv,ayv,NX,NY)
C->hsk 2018:

           print *,'RDnSEND:axt, min,max=',minval(axt),maxval(axt)
           print *,'RDnSEND:ayt, min,max=',minval(ayt),maxval(ayt)
           print *,'RDnSEND:axu, min,max=',minval(axu),maxval(axu)
           print *,'RDnSEND:ayu, min,max=',minval(ayu),maxval(ayu)
           print *,'RDnSEND:axv, min,max=',minval(axv),maxval(axv)
           print *,'RDnSEND:ayv, min,max=',minval(ayv),maxval(ayv)
           ALONt=axt
           ALATt=ayt
           ALONu=axu
           ALATu=ayu
           ALONv=axv
           ALATv=ayv
           print *,'RDnSEND:ALONt, min,max=',minval(ALONt),maxval(ALONt)
           print *,'RDnSEND:ALATt, min,max=',minval(ALATt),maxval(ALATt)
           print *,'RDnSEND:ALONu, min,max=',minval(ALONu),maxval(ALONu)
           print *,'RDnSEND:ALATu, min,max=',minval(ALATu),maxval(ALATu)
           print *,'RDnSEND:ALONv, min,max=',minval(ALONv),maxval(ALONv)
           print *,'RDnSEND:ALATv, min,max=',minval(ALATv),maxval(ALATv)

           print*,'ALONt(NX/2,NY/2): '
           print*,ALONt(NX/2,NY/2)
           print*,'ALATt(NX/2,NY/2): '
           print*,ALATt(NX/2,NY/2)

      END IF

      call OC_ANNOUNCE('(BP) to send grid arrays (6 MPI calls)',2)

      print*,'before CMP_SEND(alont,ngp)'
      call CMP_SEND(ALONt,NGP)
      print*,'after CMP_SEND(alont,ngp)'
      call CMP_SEND(ALATt,NGP)
      call CMP_SEND(ALONu,NGP)
      call CMP_SEND(ALATu,NGP)
      call CMP_SEND(ALONv,NGP)
      call CMP_SEND(ALATv,NGP)

      call OC_ANNOUNCE('the 6 grid arrays sent',1)

      call OC_ANNOUNCE('(BP) OC_RDnSENDGRIDS: returning',2)

      return
      END

C
C***********************************************************************
C
      SUBROUTINE OC_ANNOUNCE(s,DbgLev)

      USE OC_cc, ONLY: nunit_announce,VerbLev,MPI_COMM_Ocean

      implicit none

      character*(*) s
      integer DbgLev

      integer ierr
C
      if (DbgLev.le.VerbLev) then
        if (s(1:5).eq.'(BP) ') then
          call MPI_BARRIER(MPI_COMM_Ocean,ierr)
        end if
        CALL CMP_ANNOUNCE(nunit_announce,'OM: '//s)
      end if

      return
      END
C
C***********************************************************************
C
      SUBROUTINE OC_SENDSLM(mt,mu,mv)

      USE OC_cc

      implicit none

      integer, dimension(i_f:i_l,j_f:j_l) :: mt,mu,mv
   
      real fl(i_f:i_l,j_f:j_l),FG(NX,NY) !type/kind: see OC_RECVSBC

      integer j,i
C

      if (Coupler_id.lt.0) return    !   <- standalone mode

C       mt, mu, mv are supposed to be 1 at sea and 0 on land

      fl=mt
      call ASSEMBLE_cc(FG,fl)
      call CMP_SEND(FG,NGP)
      fl=mu
      call ASSEMBLE_cc(FG,fl)
      call CMP_SEND(FG,NGP)
      fl=mv
      call ASSEMBLE_cc(FG,fl)
      call CMP_SEND(FG,NGP)

      return
      END
C
C***********************************************************************
C
      SUBROUTINE OC_SENDSST(temp,ntl)

      USE OC_cc

      implicit none

      real temp(i_f:i_l,j_f:j_l,NLEV,2) ! corresponding actual arg. is
                                        ! declared as "real" in HYCOM
                                        ! (common_blocks.h). Therefore,
                                        ! this routine must be compiled
                                        ! in the same way as
                                        ! common_blocks.h so that "real"
                                        ! may mean the same
      integer ntl  ! "num. of time lev.", see code, must be 1 or 2"
      
      real sst(i_f:i_l,j_f:j_l) !corresponding dummy arg. in ASSEMBLE_cc
                                !is "real", since corresponding dummy
                                !arg. in xcaget is "real"
      real SSTG(NX,NY) ! corresponding dummy arg. in ASSEMBLE_cc
                           ! is "real", since corresponding dummy arg.
                           ! in xcaput is "real". If type/kind differs
                           ! from that of the form. arg. of CMP_SEND,
                           ! another array must be declared/used in
                           ! call CMP_SEND
      character*20 s
C

      n_ts=n_ts+1

      if (VerbLev.ge.3) write(s,'(2i10)') n_ts,i_dtc2dto
      call OC_ANNOUNCE('OC_SENDSST: n_ts, i_dtc2dto'//s,3)

      if (Coupler_id.lt.0) RETURN  !   <- standalone mode

      IF ((n_ts/i_dtc2dto)*i_dtc2dto.ne.n_ts) RETURN

      if (ntl.lt.1 .or. ntl.gt.2) then
        call GLOB_ABORT(1,'** OC_SENDSST: ntl != 1 or 2 **',1)
      end if

      if (NX.ne.imt .or. NY.ne.jmt) then
        call GLOB_ABORT(1,
     >  '** OC_RECVSBC: NX.ne.imt.or.NY.ne.jmt',1)
      end if
             ! NX, NY are sizes of array for which interpolated
             ! values are computed by C. imt, jmt are sizes of whole
             ! grid array in HYCOM. If the two pairs are not the same
             ! (normally, it can be that imt>NX and/or jmt>NY
             ! because of boundaries), new array SSTG1(imt,jmt) needs to
             ! be declared and used in call ASSEMBLE_cc, then SSTG be
             ! defined as SSTG=SSTG1(x:x+NX-1,y:y+NY-1) and used
             ! call CMP_SEND

      sst=temp(:,:,1,ntl)
      call OC_ANNOUNCE('OC_SENDSST: to call ASSEMBLE_cc(SSTG,sst)',3)

      call ASSEMBLE_cc(SSTG,sst)

      call CMP_SEND(SSTG,NGP)

      call OC_ANNOUNCE('OC_SENDSST: to return',3)

      return
      END

C
C***********************************************************************
C
cBT --> hsk: to send a set of ocean currents at a given level
      SUBROUTINE OC_SENDSSC(u3d,v3d,ntl)
c
      USE OC_cc
      USE WW3_cc
c
      implicit none
c
      real u3d(i_f:i_l,j_f:j_l,NLEV,2),
     >     v3d(i_f:i_l,j_f:j_l,NLEV,2)
					! corresponding actual arg. is
                                        ! declared as "real" in HYCOM
                                        ! (common_blocks.h). Therefore,
                                        ! this routine must be compiled
                                        ! in the same way as
                                        ! common_blocks.h so that "real"
                                        ! may mean the same
      integer ntl  ! "num. of time lev.", see code, must be 1 or 2"
      real ul(i_f:i_l,j_f:j_l) 
      real vl(i_f:i_l,j_f:j_l)
c
      character*20 s
C
      io2w=2

      if (VerbLev.ge.3) write(s,'(2i10)') n_ts,i_dtc2dto
      call OC_ANNOUNCE('OC_SENDSSC: n_ts, i_dtc2dto'//s,3)
c
      if (io2a .LT. 2 .and. io2w .LT. 2) RETURN ! <- no surface currents passed to ATM or WW3
      if (Coupler_id.lt.0) RETURN  !   <- standalone mode
      if (Waves_id.lt.0) RETURN  !   <- No WM

      IF ((n_ts/i_dtc2dto)*i_dtc2dto.ne.n_ts) RETURN
      if (ntl.lt.1 .or. ntl.gt.2) then
        print*,'ntl=',ntl
        call GLOB_ABORT(1,'** OC_SENDSSC: ntl != 1 or 2 **',1)
      end if

      if (NX.ne.imt .or. NY.ne.jmt) then
        call GLOB_ABORT(1,
     >  '** OC_SENDSSC: NX.ne.imt.or.NY.ne.jmt',1)
      end if
             ! NX, NY are sizes of array for which interpolated
             ! values are computed by C. imt, jmt are sizes of whole
             ! grid array in HYCOM. If the two pairs are not the same
             ! (normally, it can be that imt>NX and/or jmt>NY
             ! because of boundaries), new array SSTG1(imt,jmt) needs to
             ! be declared and used in call ASSEMBLE_cc, then USFCG and VSFCG be
             ! defined as USFCG=USFCG1(x:x+NX-1,y:y+NY-1) and VSFCG=VSFCG1(x:x+NX-1,y:y+NY-1),
	     ! and used  
	     ! call CMP_SEND
c
      ul=u3d(:,:,1,ntl)    ! surface u-com. velocity
      vl=v3d(:,:,1,ntl)    ! surface v-com. velocity
c

      call OC_ANNOUNCE('OC_SENDSSC: to call ASSEMBLE_cc(sscx,u2d)',3)
      call ASSEMBLE_cc(SSCX,ul)
      call CMP_SEND(SSCX,NGP)

      call OC_ANNOUNCE('OC_SENDSSC: to call ASSEMBLE_cc(sscy,v2d)',3)
      call ASSEMBLE_cc(SSCY,vl)
      call CMP_SEND(SSCY,NGP)

      call OC_ANNOUNCE('OC_SENDSSC: to return',3)

      return
      END
c->hsk
C
C***********************************************************************
C
C-> hsk 2/18/2016: for wave coupling
c     passing deep (background) currents (for POM), or 
c     mixed layer currents (for HYCOM)
c
      SUBROUTINE OC_SENDDPC(u3d,v3d,ntl)
c
      USE OC_cc
      USE WW3_cc
c
      IMPLICIT NONE
c
      real u3d(i_f:i_l,j_f:j_l,NLEV,2),
     >     v3d(i_f:i_l,j_f:j_l,NLEV,2)
      integer ntl  
      real u4ww(i_f:i_l,j_f:j_l),v4ww(i_f:i_l,j_f:j_l)
c
      character*20 s
c
      if (VerbLev.ge.3) write(s,'(2i10)') n_ts,i_dtc2dto
      call OC_ANNOUNCE('OC_SENDDPC: n_ts, i_dtc2dto'//s,3)
c
      if (io2w .LT. 1) RETURN
      if (Coupler_id.lt.0) RETURN  !   <- standalone mode
      if (Waves_id.lt.0) RETURN  !   <- No WM
c
      IF ((n_ts/i_dtc2dto)*i_dtc2dto.ne.n_ts) RETURN
      if (ntl.lt.1 .or. ntl.gt.2) then
        print*,'ntl=',ntl
        call GLOB_ABORT(1,'** OC_SENDSSC: ntl != 1 or 2 **',1)
      end if

      if (NX.ne.imt .or. NY.ne.jmt) then
        call GLOB_ABORT(1,
     >  '** OC_SENDDPC: NX.ne.imt.or.NY.ne.jmt',1)
      end if

      u4ww=u3d(:,:,10,ntl)    ! surface u-com. velocity
      v4ww=v3d(:,:,10,ntl)    ! surface v-com. velocity
c
      call OC_ANNOUNCE('OC_SENDDPC: to call ASSEMBLE_cc(dpcx,u4w)',3)
      call ASSEMBLE_cc(DPCX,u4ww)
      call CMP_SEND(DPCX,NGP)
c
      call OC_ANNOUNCE('OC_SENDDPC: to call ASSEMBLE_cc(dpcy,v4w)',3)
      call ASSEMBLE_cc(DPCY,v4ww)
      call CMP_SEND(DPCY,NGP)
c
      call OC_ANNOUNCE('OC_SENDDPC: to return',3)
c
      return
      END
c->hsk
c
C
C***********************************************************************
C    sending the KPP surface boundary layer depth to WW3
CBT
      SUBROUTINE OC_SENDKPP(kpph)

      USE OC_cc
      USE WW3_cc

      IMPLICIT NONE

      INTEGER i, j
      REAL kpph(i_f:i_l,j_f:j_l)
      character*20 s

      if (VerbLev.ge.3) write(s,'(2i10)') n_ts,i_dtc2dto
      call OC_ANNOUNCE('OC_SENDKPP: n_ts, i_dtc2dto'//s,3)

      if (io2w .LT. 3) RETURN
      if (Coupler_id.lt.0) RETURN  !   <- standalone mode
      if (Waves_id.lt.0) RETURN  !   <- No WM

      IF ((n_ts/i_dtc2dto)*i_dtc2dto.ne.n_ts) RETURN

      if (NX.ne.IMt.or. NY.ne.JMt) then
        call GLOB_ABORT(1,
     >  '** OC_SENDKPP: NX.ne.imt.or.NY.ne.jmt',1)
      end if

      call ASSEMBLE_cc(KPPML,kpph)
      call CMP_SEND(KPPML,NGP)

      call OC_ANNOUNCE('OC_SENDKPP: to return',3)


      return
      END

CBT.
C
C***********************************************************************
C
      SUBROUTINE OC_RECV_SBC(SF)

      USE OC_cc

      USE SFLUX_cc

      implicit none

      real SF(i_f:i_l,j_f:j_l,nc)     ! corresponding actual args are
                                      ! declared as "real" in HYCOM
                                      ! (common_blocks.h). Therefore,
                                      ! this routine must be compiled in
                                      ! the same way as common_blocks.h
                                      ! so that "real" may mean the same
                                      ! (see also below about F)
                                           
      real F(NX,NY) ! corresponding dummy arg. in DISASSEMBLE_cc
                        ! is "real", since corresponding dummy arg.
                        ! in xcaput is "real". If the type/kind differs
                        ! from that of the form. arg. of CMP_RECV,
                        ! another array must be declared/used in
                        ! call CMP_RECV
      real fl(i_f:i_l,j_f:j_l) !corresponding dummy a. in DISASSEMBLE_cc
                               !is "real", since corresponding dummy
                               !arg. in xcaput is "real"
      real too_low /-1.E20/ ! must be >= very_large_negative in
                            ! interp. routine, currently -1.E30
C
C--- hsk 2018:
      real prsbas /101300.0/  ! reference pressure for use to HYCOM (--> mslprs)
C

      integer i,j,m,n
      integer nts,n_ts_old/-100/
      logical SENDSSTcomesFIRST/.true./
      save too_low,n_ts_old,SENDSSTcomesFIRST,n
C

      call OC_ANNOUNCE('OC_RECV_SBC entered',3)
c        print*,'OC_RECV_SBC: entered'

      if (NX.ne.imt .or. NY.ne.jmt) then
        call GLOB_ABORT(1,'** OC_RECVSBC: NX.ne.imt.or.NY.ne.jmt',1)
      end if
             ! NX, NY are sizes of array for which interpolated
             ! values are computed by C. imt, jmt are sizes of whole
             ! grid array in HYCOM. If the two pairs are not the same
             ! (normally, it can be that imt>NX and/or jmt>NY
             ! because of boundaries), new array F1(imt,jmt) needs to
             ! be declared, then defined as F1(x:x+NX-1,y+NY-1)=F,
             ! then boundary values (1:x-1,x+NX:imt,1:y-1,y+NY:jmt)
             ! be defined for F1, then F1 (rather than F) be used in
             ! DISASSEMBLE_cc

      if (n_ts.eq.-1) SENDSSTcomesFIRST=.false.
      if (SENDSSTcomesFIRST) then
        nts=n_ts
      else
        nts=n_ts+1
      end if

      if (n_ts.eq.n_ts_old) then
        n=n+1
      else
        n=1
        n_ts_old=n_ts
      end if


      call GLOB_ABORT(max(n-num_sflx,0),
     >'number of surf. flux exceeds num_sflx in OC_RECVSBC',1)

      if (Coupler_id.lt.0) return     !   <- standalone mode

      IF ((nts/i_dtc2dto)*i_dtc2dto.eq.nts) THEN

        call CMP_RECV(F,NGP)

        call DISASSEMBLE_cc(F,fl)
        sflx(:,:,n)=fl

      ELSE

        fl=sflx(:,:,n)

      END IF
                                   
      do m=1,nc
        do j=j_f,j_l
          do i=i_f,i_l
            if (fl(i,j).gt.too_low) then
              SF(i,j,m)=fl(i,j)
              if (m.eq.4) SF(i,j,m)=SF(i,j,m)-prsbas ! <- hsk@2018 for use to mslprs in HYCOM
            else if (missing_value_flag.ne.0.) then
              SF(i,j,m)=missing_value_flag
            end if
          end do
        end do
      end do
C
      call OC_ANNOUNCE('OC_RECV_SBC to return',3)

      return
      END
C
C***********************************************************************
C
C<- hsk @5/31/2017: Modified to suit for HYCOM
c       
       SUBROUTINE OC_RECV_DTAU(ttaux,ttauy)
c
       USE OC_cc
       USE WW3_cc
       IMPLICIT NONE
c
       integer i,j,n,m
c
       real ttaux(i_f:i_l,j_f:j_l)     ! vars. that HYCOM reads in mod_HYCOM.F 
       real ttauy(i_f:i_l,j_f:j_l)     ! vars. that HYCOM reads in mod_HYCOM.F 
c
       real, parameter :: dtaumax = 1.5
c
       INTEGER nts,n_ts_old/-100/
       logical SENDSSTcomesFIRST/.true./
       save n_ts_old,SENDSSTcomesFIRST,n
c
       call OC_ANNOUNCE('OC_RECV_DTAU entered',3)
c
       if (NX.ne.imt .or. NY.ne.jmt) then
          call GLOB_ABORT(1,'** OC_RECV_DTAU: NX.ne.imt.or.NY.ne.jmt',1)
       end if
c
       if (n_ts.eq.-1) SENDSSTcomesFIRST=.false.
       if (SENDSSTcomesFIRST) then
         nts=n_ts
       else
         nts=n_ts+1
       end if
c
!      if (n_ts.eq.n_ts_old) then
!        n=n+1
!      else
!        n=1
!        n_ts_old=n_ts
!      end if

      call GLOB_ABORT(max(n-num_sc,0),
     >'number of WW3 dtau exceeds num_sc in OC_RECVSBC',1)
c
      if (iw2o .LT. 1) RETURN
      if (Coupler_id.lt.0) return     !   <- standalone mode
      if (Waves_id.lt.0) RETURN  !   <- No WM
c
      IF ((nts/i_dtc2dto)*i_dtc2dto.eq.nts) THEN
        call CMP_RECV(DTXG,NGP)
        call DISASSEMBLE_cc(DTXG,dtxc)
        call OC_ANNOUNCE('OC_RECV_DTAU: received and tiled dtaux',3)

        call CMP_RECV(DTYG,NGP)
        call DISASSEMBLE_cc(DTYG,dtyc)
        call OC_ANNOUNCE('OC_RECV_DTAU: received and tiled dtauy',3)

      ENDIF
c
      DO j=j_f,j_l
        DO i=i_f,i_l
          IF ( ABS(dtxc(i,j)) .lt. dtaumax ) then
              ttaux(i,j)=dtxc(i,j)
          ELSE
              ttaux(i,j) = 0.0
          ENDIF
c
          IF ( ABS(dtyc(i,j)) .lt. dtaumax ) then
              ttauy(i,j)=dtyc(i,j)
          ELSE
              ttauy(i,j) = 0.0
          ENDIF
        ENDDO
      ENDDO
c
      call OC_ANNOUNCE('OC_RECV_DTAU to return',3)

      return
      END
c
CBT.
C
C***********************************************************************
Chsk:  HYCOM won't use. However, set it but for dummy. @2017
CBT
      SUBROUTINE OC_RECV_WBCOND(twbc)
      USE OC_cc
      USE WW3_cc
      IMPLICIT NONE

      INTEGER :: i, j
      REAL twbc(i_f:i_l,j_f:j_l)

      REAL :: PARAMETER, ulim = 0.05, llim = -0.05, 
     &    misval =  -1.E+30

      INTEGER nts,n_ts_old/-100/
      logical SENDSSTcomesFIRST/.true./
      save n_ts_old,SENDSSTcomesFIRST

      call OC_ANNOUNCE('OC_RECV_WBCOND entered',3)

      if (NX.ne.imt .or. NY.ne.jmt) then
       call GLOB_ABORT(1,'** OC_RECV_WBCOND: NX.ne.imt.or.NY.ne.jmt',1)
      endif

      if (n_ts.eq.-1) SENDSSTcomesFIRST=.false.
      if (SENDSSTcomesFIRST) then
        nts=n_ts
      else
        nts=n_ts+1
      end if

      if (iw2o .LT. 1) RETURN
      if (Coupler_id.lt.0) return     !   <- standalone mode
      if (Waves_id.lt.0) RETURN  !   <- No WM

      IF ((nts/i_dtc2dto)*i_dtc2dto.eq.nts) THEN
        call CMP_RECV(WBC,NGP)
        call OC_ANNOUNCE('OC_RECV_WBCOND: back from
     &                    CMP_RECV(wbcond...',3)
        call DISASSEMBLE_cc(WBC,bcondw)
        call OC_ANNOUNCE('OC_RECV_WBCOND: DISASSEMBLE wbcond',3)

        DO j = j_f,j_l
        DO i = i_f,i_l
           IF (bcondw(i,j) .LE. misval) bcondw(i,j) = 0.0
           IF (bcondw(i,j) .LT. llim) THEN
              twbc(i,j) = llim
           ELSE IF (bcondw(i,j) .GT. ulim) THEN
              twbc(i,j) = ulim
           ELSE
              twbc(i,j) = bcondw(i,j)
           ENDIF
        ENDDO
        ENDDO
      ENDIF

      call OC_ANNOUNCE('OC_RECV_WBCOND to return',3)

      return
      END

cCBT + hsk.
c
C***********************************************************************
C
Chsk  Converting a mean wavelength for mean surface Stokes Drifts
c     to mean wavenumber
c 
c       Modified for HYCOM coupling

      SUBROUTINE OC_RECV_MDPTH(tmnWL)
      USE OC_cc
      USE WW3_cc
      IMPLICIT NONE

      INTEGER i,j,n,m
      integer nbin     ! passed from HYCOM (same as nbin defined in mod_stokes.F)
                       ! representing number of partitioned Stokes Drift
c
      REAL, PARAMETER :: pi4inv=1.0/(2.0*2.0*3.141593)

      REAL, PARAMETER :: wnulim = 300.0*pi4inv
c
      real tmnWL(i_f:i_l,j_f:j_l)  ! var. that are read in HYCOM
c
c
      INTEGER nts,n_ts_old/-100/
      logical SENDSSTcomesFIRST/.true./
      save n_ts_old,SENDSSTcomesFIRST,n

      call OC_ANNOUNCE('OC_RECV_MDPTH entered',3)

      if (NX.ne.imt .or. NY.ne.jmt) then
        call GLOB_ABORT(1,'** OC_RECV_MDPTH: NX.ne.imt.or.NY.ne.jmt',1)
      end if

      if (n_ts.eq.-1) SENDSSTcomesFIRST=.false.
      if (SENDSSTcomesFIRST) then
        nts=n_ts
      else
        nts=n_ts+1
      end if

!      if (n_ts.eq.n_ts_old) then
!        n=n+1
!      else
!        n=1
!        n_ts_old=n_ts
!      end if

      if (iw2o .LT. 1) RETURN
      if (Coupler_id.lt.0) return     !   <- standalone mode
      if (Waves_id.lt.0) RETURN  !   <- No WM

      IF ((nts/i_dtc2dto)*i_dtc2dto.eq.nts) THEN
        call CMP_RECV(AVGWL,NGP)
        call DISASSEMBLE_cc(AVGWL,mnwl)
        call OC_ANNOUNCE('OC_RECV_MDPTH: DISASSEMBLE_cc WLG 
     +        to WLc ',3)
      ENDIF
c
       DO j=j_f,j_l
       DO i=i_f,i_l
           IF (mnwl(i,j).LE.0.0) then
              tmnWL(i,j)=0.0
           ELSE if (mnwl(i,j).GT.300.) then
              tmnWL(i,j)=wnulim
           ELSE
              tmnWL(i,j)=mnwl(i,j)*pi4inv
           ENDIF
        ENDDO
        ENDDO
c
      call OC_ANNOUNCE('OC_RECV_MDPTH to return',3)
c
      return
      END 
C
C***********************************************************************
C
c<-hsk
      SUBROUTINE OC_RECV_STKDF(tstkx,tstky)
      USE OC_cc
      USE WW3_cc
      IMPLICIT NONE

      INTEGER :: i,j,n,m
      REAL tstkx(i_f:i_l,j_f:j_l)     ! vars. that HYCOM reads in.
      REAL tstky(i_f:i_l,j_f:j_l)
c
      real stkc(i_f:i_l,j_f:j_l) !corresponding dummy a. in DISASSEMBLE_cc
                               !is "real", since corresponding dummy
                               !arg. in xcaput is "real"
      REAL, PARAMETER :: ulim = 1.0,  llim = -1.0
     
      INTEGER nts,n_ts_old/-100/
      logical SENDSSTcomesFIRST/.true./
      save n_ts_old,SENDSSTcomesFIRST,n

      call OC_ANNOUNCE('OC_RECV_STKDFT entered',3)

      if (NX.ne.imt .or. NY.ne.jmt) then
        call GLOB_ABORT(1,'** OC_RECV_STKDF: NX.ne.imt.or.NY.ne.jmt',1)
      end if

      if (n_ts.eq.-1) SENDSSTcomesFIRST=.false.
      if (SENDSSTcomesFIRST) then
        nts=n_ts
      else
        nts=n_ts+1
      end if

!      if (n_ts.eq.n_ts_old) then
!        n=n+1
!      else
!        n=1
!        n_ts_old=n_ts
!      end if

      call GLOB_ABORT(max(n-num_sc,0),
     >'number of WW3 dtau exceeds num_ww3 in OC_RECVSBC',1)

      if (iw2o .LT. 2) RETURN
      if (Coupler_id.lt.0) return     !   <- standalone mode
      if (Waves_id.lt.0) RETURN  !   <- No WM

      IF ((nts/i_dtc2dto)*i_dtc2dto.eq.nts) THEN
        call CMP_RECV(STDX,NGP)
        call DISASSEMBLE_cc(STDX,xstk)
        call OC_ANNOUNCE('OC_RECV_STKDF: received and tiled xstk...',3)

        call CMP_RECV(STDY,NGP)
        call DISASSEMBLE_cc(STDY,ystk)
        call OC_ANNOUNCE('OC_RECV_STKDF: received and tiled xstk...',3)

      ENDIF

      DO j=j_f,j_l
      DO i=i_f,i_l
         if ( xstk(i,j).le.too_low ) then
           tstkx(i,j)=0.0
         else
           tstkx(i,j)=max(min(xstk(i,j), ulim), llim)
         endif
c
         if ( ystk(i,j).le.too_low ) then
           tstky(i,j)=0.0
         else
           tstky(i,j)=max(min(ystk(i,j), ulim), llim)
         endif

      ENDDO
      ENDDO
c
      call OC_ANNOUNCE('OC_RECV_STKDF to return',3)

      return
      END
c->hsk.

cBT.+hsk
c
C***********************************************************************
c --> hsk @5/31/2017: for 3-way coupling
c       receiving stokes drift from WW3, followed by
c       generating vertical profiles for each SD component
c       for a given set of fixed depths.
c
      SUBROUTINE OC_RECV_3STKDFT(sdx,sdy,sdw)
      USE OC_cc
      USE WW3_cc

      IMPLICIT NONE

      integer i,j,k
c
      real sdx(i_f:i_l,j_f:j_l,num_sd),      ! vars. that are read in HYCOM
     > sdy(i_f:i_l,j_f:j_l,num_sd),
     > sdw(i_f:i_l,j_f:j_l,num_sd)
c
      real missing_value_flag /-1.E30/ ! see subr-s OC_INIT, OC_RECV_SBC
c
      INTEGER nts,n_ts_old/-100/
      logical SENDSSTcomesFIRST/.true./
      save n_ts_old,SENDSSTcomesFIRST
c
      call OC_ANNOUNCE('OC_RECV_STKDFT entered',3)
c
      if (NX.ne.imt .or. NY.ne.jmt) then
        call GLOB_ABORT(1,'** OC_RECV_STKDFT: NX.ne.imt.or.NY.ne.jmt',1)
      end if
c
      if (n_ts.eq.-1) SENDSSTcomesFIRST=.false.
      if (SENDSSTcomesFIRST) then
        nts=n_ts
      else
        nts=n_ts+1
      end if
c
      if (iw2o .LT. 2) RETURN
      if (Coupler_id.lt.0) return     !   <- standalone mode
      if (Waves_id.lt.0) RETURN  !   <- No WM
c
      IF ((nts/i_dtc2dto)*i_dtc2dto.eq.nts) THEN
c
        call CMP_RECV(STDX3,NGP)
        call DISASSEMBLE_cc(STDX3,xstk3)

        call CMP_RECV(STDY3,NGP)
        call DISASSEMBLE_cc(STDY3,ystk3)

        call DISASSEMBLE_cc(P3WL,wl3b)
        call CMP_RECV(P3WL,NGP)

        call OC_ANNOUNCE('OC_RECV_3STKDFT: ...
     >  DISASSEMBLE_cc (STDx3,STDy3,WL3) to (xstk3,ystk3,wl3b) ',3)
      END IF

      do k = 1, num_sd
      do j = j_f, j_l
        do i = i_f, i_l
           IF (xstk3(i,j,k) .ne. missing_value_flag) THEN
             sdx(i,j,k) = xstk3(i,j,k)
           ELSE
             sdx(i,j,k) = missing_value_flag
           ENDIF
           IF (ystk3(i,j,k) .ne. missing_value_flag) THEN
             sdy(i,j,k) = ystk3(i,j,k)
           ELSE
             sdy(i,j,k) = missing_value_flag
           ENDIF
           IF (wl3b(i,j,k) .ne. missing_value_flag) THEN
             sdw(i,j,k) = wl3b(i,j,k)
           ELSE
             sdw(i,j,k) = missing_value_flag
           ENDIF
        ENDDO
      ENDDO
      ENDDO
c
      call OC_ANNOUNCE('OC_RECV_3STKDF to return',3)
c
      return
      END
c

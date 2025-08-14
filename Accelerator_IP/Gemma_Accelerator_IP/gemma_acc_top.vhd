library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity Accelerator_Top is
    Port (  s_axi_aclk 			: 	in 	  STD_LOGIC;                                    
			s_axi_aresetn 		: 	in 	  STD_LOGIC;                                                      
		      
			----- Master Write Address Channel ------  	                
    		m_axi_awvalid		: out std_logic;
    		m_axi_awid		    : out std_logic_vector(11 downto 0);
    		m_axi_awlen		    : out std_logic_vector(7 downto 0);
    		m_axi_awsize		: out std_logic_vector(2 downto 0);
    		m_axi_awburst		: out std_logic_vector(1 downto 0);
    		m_axi_awlock		: out std_logic_vector(0 downto 0);
    		m_axi_awcache		: out std_logic_vector(3 downto 0);
    		m_axi_awqos		    : out std_logic_vector(3 downto 0);
    		m_axi_awaddr		: out std_logic_vector(63 downto 0);
    		m_axi_awprot		: out std_logic_vector(2 downto 0);    		
    		m_axi_awready		: in  std_logic;
    		
			----- Master Write Data Channel ------  	
    		m_axi_wvalid		: out std_logic;
    		m_axi_wlast		    : out std_logic;
    		m_axi_wdata		    : out std_logic_vector(127 downto 0);
    		m_axi_wstrb		    : out std_logic_vector(15 downto 0);
    		m_axi_wready		: in  std_logic;
    	
			----- Master Write Response Channel ------  	
    		m_axi_bready		: out std_logic;
    		m_axi_bvalid		: in  std_logic;
    		m_axi_bid			: in  std_logic_vector(11 downto 0);
    		m_axi_bresp		    : in  std_logic_vector(1 downto 0);
    	
			----- Master Read Address Channel ------  	
    		m_axi_arvalid		: out std_logic;
    		m_axi_arid		    : out std_logic_vector(11 downto 0);
    		m_axi_arlen		    : out std_logic_vector(7 downto 0);
    		m_axi_arsize		: out std_logic_vector(2 downto 0);
    		m_axi_arburst		: out std_logic_vector(1 downto 0);
    		m_axi_arlock		: out std_logic_vector(0 downto 0);
    		m_axi_arcache		: out std_logic_vector(3 downto 0);
    		m_axi_arqos		    : out std_logic_vector(3 downto 0);
    		m_axi_araddr		: out std_logic_vector(63 downto 0);
    		m_axi_arprot		: out std_logic_vector(2 downto 0);
    		m_axi_arready		: in  std_logic;
    
			----- Master Read Response Channel ------  	
    		m_axi_rready		: out std_logic;
    		m_axi_rvalid		: in  std_logic;
    		m_axi_rid			: in  std_logic_vector(11 downto 0);
    		m_axi_rlast		    : in  std_logic;
    		m_axi_rresp		    : in  std_logic_vector(1 downto 0);
    		m_axi_rdata		    : in  std_logic_vector(127 downto 0);
    		                                                
			----- Slave Write Address Channel ------                        
			s_axi_awid  		:  	in    std_logic_vector	(11  downto 0); 
			s_axi_awaddr		:  	in    std_logic_vector	(63  downto 0); 
			s_axi_awlen 		:  	in    std_logic_vector	(7   downto 0); 
			s_axi_awsize		:  	in    std_logic_vector	(2   downto 0); 
			s_axi_awburst  		:  	in    std_logic_vector	(1   downto 0); 
			s_axi_awlock		:  	in    std_logic; 
			s_axi_awcache		:  	in    std_logic_vector	(3   downto 0); 
			s_axi_awprot		:  	in    std_logic_vector	(2   downto 0); 
			s_axi_awqos 		:  	in    std_logic_vector	(3   downto 0); 
			s_axi_awvalid  		:  	in    std_logic;                        
			s_axi_awready 		:  	out   std_logic;                        
			----- Slave Write Data Channel ------                          
			s_axi_wdata  		:  	in 	  std_logic_vector	(127 downto 0); 
			s_axi_wstrb  		:  	in 	  std_logic_vector	(15  downto 0); 
			s_axi_wlast  		:  	in 	  std_logic;                        
			s_axi_wvalid 		:  	in 	  std_logic;                        
			s_axi_wready 		:  	out	  std_logic;                        
			----- Slave Write Response Channel ------                       
			s_axi_bready 		: 	in    std_logic;                        
			s_axi_bid	 		: 	out   std_logic_vector	(11  downto 0); 
			s_axi_bresp  		: 	out   std_logic_vector	(1   downto 0); 
			s_axi_bvalid 		: 	out   std_logic;                        
			----- Slave Read Address Channel ------                         
			s_axi_arid   		:   in    std_logic_vector	(11  downto 0); 
			s_axi_araddr 		:	in    std_logic_vector	(63  downto 0); 
			s_axi_arlen  		:	in    std_logic_vector	(7 	 downto 0); 
			s_axi_arsize 		:	in    std_logic_vector	(2 	 downto 0); 
			s_axi_arburst		:	in    std_logic_vector	(1 	 downto 0); 
			s_axi_arlock 		:	in    std_logic; 
			s_axi_arcache		:	in    std_logic_vector	(3 	 downto 0); 
			s_axi_arprot 		:	in    std_logic_vector	(2 	 downto 0); 
			s_axi_arqos  		:	in    std_logic_vector	(3 	 downto 0); 
			s_axi_arvalid		:	in    std_logic;                        
			s_axi_arready		:	out   std_logic;                          
			----- Slave Read Data Channel ------                            
			s_axi_rready 		: 	in    std_logic;                        
			s_axi_rid    		: 	out   std_logic_vector	(11  downto 0); 
			s_axi_rdata  		: 	out   std_logic_vector	(127 downto 0); 
			s_axi_rresp  		: 	out   std_logic_vector	(1   downto 0); 
			s_axi_rlast  		: 	out   std_logic;                        
			s_axi_rvalid 		: 	out   std_logic 
           );
end Accelerator_Top;

architecture Accelerator_Top_a of Accelerator_Top is  	
   
    COMPONENT gemma_accelerator
      GENERIC (
        ID_WIDTH : integer := 12
      );
      PORT (
        -- Clock / Reset
        ap_clk   : IN  std_logic;
        ap_rst_n : IN  std_logic;
        -- AXI-Lite control
        s_axi_control_awvalid : IN  std_logic;
        s_axi_control_awready : OUT std_logic;
        s_axi_control_awaddr  : IN  std_logic_vector(7 downto 0);
        s_axi_control_wvalid  : IN  std_logic;
        s_axi_control_wready  : OUT std_logic;
        s_axi_control_wdata   : IN  std_logic_vector(31 downto 0);
        s_axi_control_wstrb   : IN  std_logic_vector(3 downto 0);
        s_axi_control_bvalid  : OUT std_logic;
        s_axi_control_bready  : IN  std_logic;
        s_axi_control_bresp   : OUT std_logic_vector(1 downto 0);
        s_axi_control_awid    : IN  std_logic_vector(0 downto 0);
        s_axi_control_bid     : OUT std_logic_vector(0 downto 0);
        s_axi_control_arvalid : IN  std_logic;
        s_axi_control_arready : OUT std_logic;
        s_axi_control_araddr  : IN  std_logic_vector(7 downto 0);
        s_axi_control_rvalid  : OUT std_logic;
        s_axi_control_rready  : IN  std_logic;
        s_axi_control_rdata   : OUT std_logic_vector(31 downto 0);
        s_axi_control_rresp   : OUT std_logic_vector(1 downto 0);
        s_axi_control_arid    : IN  std_logic_vector(0 downto 0);
        s_axi_control_rid     : OUT std_logic_vector(0 downto 0);
        -- AXI-4 Master memory
        m_axi_gmem_awid    : OUT std_logic_vector(ID_WIDTH-1 downto 0);
        m_axi_gmem_bid     : IN  std_logic_vector(ID_WIDTH-1 downto 0);
        m_axi_gmem_awvalid : OUT std_logic;
        m_axi_gmem_awready : IN  std_logic;
        m_axi_gmem_awaddr  : OUT std_logic_vector(63 downto 0);
        m_axi_gmem_awlen   : OUT std_logic_vector(7  downto 0);
        m_axi_gmem_awsize  : OUT std_logic_vector(2  downto 0);
        m_axi_gmem_awburst : OUT std_logic_vector(1  downto 0);
        m_axi_gmem_wvalid  : OUT std_logic;
        m_axi_gmem_wready  : IN  std_logic;
        m_axi_gmem_wdata   : OUT std_logic_vector(127 downto 0);
        m_axi_gmem_wstrb   : OUT std_logic_vector(15  downto 0);
        m_axi_gmem_wlast   : OUT std_logic;
        m_axi_gmem_bvalid  : IN  std_logic;
        m_axi_gmem_bready  : OUT std_logic;
        m_axi_gmem_bresp   : IN  std_logic_vector(1   downto 0);
        m_axi_gmem_arid    : OUT std_logic_vector(ID_WIDTH-1 downto 0);
        m_axi_gmem_rid     : IN  std_logic_vector(ID_WIDTH-1 downto 0);
        m_axi_gmem_arvalid : OUT std_logic;
        m_axi_gmem_arready : IN  std_logic;
        m_axi_gmem_araddr  : OUT std_logic_vector(63 downto 0);
        m_axi_gmem_arlen   : OUT std_logic_vector(7  downto 0);
        m_axi_gmem_arsize  : OUT std_logic_vector(2  downto 0);
        m_axi_gmem_arburst : OUT std_logic_vector(1  downto 0);
        m_axi_gmem_rvalid  : IN  std_logic;
        m_axi_gmem_rready  : OUT std_logic;
        m_axi_gmem_rdata   : IN  std_logic_vector(127 downto 0);
        m_axi_gmem_rlast   : IN  std_logic;
        m_axi_gmem_rresp   : IN  std_logic_vector(1   downto 0)
      );
    END COMPONENT;

    -- Internal signals for width conversion
    signal control_awaddr : std_logic_vector(7 downto 0);
    signal control_araddr : std_logic_vector(7 downto 0);
    signal control_wdata  : std_logic_vector(31 downto 0);
    signal control_wstrb  : std_logic_vector(3 downto 0);
    signal control_rdata  : std_logic_vector(31 downto 0);
    signal control_awid   : std_logic_vector(0 downto 0);
    signal control_arid   : std_logic_vector(0 downto 0);
    signal control_bid    : std_logic_vector(0 downto 0);
    signal control_rid    : std_logic_vector(0 downto 0);
    
    -- Internal signals from accelerator for ID mapping
    signal m_axi_gmem_awid_internal : std_logic_vector(11 downto 0);
    signal m_axi_gmem_arid_internal : std_logic_vector(11 downto 0);

begin 

    -- Handle unused AXI4 master signals (set to safe defaults)
    m_axi_awlock  <= "0";
    m_axi_awcache <= "0010";  -- Normal Non-cacheable Bufferable
    m_axi_awqos   <= "0000";
    m_axi_awprot  <= "000";
    m_axi_arlock  <= "0"; 
    m_axi_arcache <= "0010";  -- Normal Non-cacheable Bufferable
    m_axi_arqos   <= "0000";
    m_axi_arprot  <= "000";

    -- AXI-Lite control interface width conversion (64-bit slave to 32-bit accelerator)
    -- Address conversion (use lower 8 bits for expanded debug register access)
    control_awaddr <= s_axi_awaddr(7 downto 0);
    control_araddr <= s_axi_araddr(7 downto 0);
    
    -- Data width conversion (select 32-bit word based on address bits [3:2])
    control_wdata <= s_axi_wdata(31 downto 0)   when s_axi_awaddr(3 downto 2) = "00"  else
                     s_axi_wdata(63 downto 32)  when s_axi_awaddr(3 downto 2) = "01"  else
                     s_axi_wdata(95 downto 64)  when s_axi_awaddr(3 downto 2) = "10"  else
                     s_axi_wdata(127 downto 96);

    control_wstrb <= s_axi_wstrb(3 downto 0)    when s_axi_awaddr(3 downto 2) = "00"  else
                     s_axi_wstrb(7 downto 4)    when s_axi_awaddr(3 downto 2) = "01"  else
                     s_axi_wstrb(11 downto 8)   when s_axi_awaddr(3 downto 2) = "10"  else
                     s_axi_wstrb(15 downto 12);

    -- ID conversion (12-bit to 1-bit)
    control_awid(0) <= s_axi_awid(0);
    control_arid(0) <= s_axi_arid(0);

    -- Read data expansion (replicate 32-bit to 128-bit)
    s_axi_rdata <= control_rdata & control_rdata & control_rdata & control_rdata;
    
    -- ID passthrough (from your original code)
    s_axi_bid <= s_axi_awid;
    s_axi_rid <= s_axi_arid;
    
    -- Always last for single-beat reads
    s_axi_rlast <= '1';
    
    -- Master AXI ID mapping (from your original code with prefix)
    -- Using the accelerator's internal IDs with your specific prefix
    m_axi_arid <= "00100000000" & m_axi_gmem_arid_internal(0 downto 0);
    m_axi_awid <= "00100000000" & m_axi_gmem_awid_internal(0 downto 0);

    ------------------------------------------------------------------------
    -- Instantiate the accelerator
    ------------------------------------------------------------------------
    inst_gemma_accel : gemma_accelerator
      GENERIC MAP (
        ID_WIDTH => 12
      )
      PORT MAP (
        -- Clock / Reset
        ap_clk   => s_axi_aclk,
        ap_rst_n => s_axi_aresetn,

        -- AXI-Lite control (width converted)
        s_axi_control_awvalid => s_axi_awvalid,
        s_axi_control_awready => s_axi_awready,
        s_axi_control_awaddr  => control_awaddr,
        s_axi_control_wvalid  => s_axi_wvalid,
        s_axi_control_wready  => s_axi_wready,
        s_axi_control_wdata   => control_wdata,
        s_axi_control_wstrb   => control_wstrb,
        s_axi_control_bvalid  => s_axi_bvalid,
        s_axi_control_bready  => s_axi_bready,
        s_axi_control_bresp   => s_axi_bresp,
        s_axi_control_awid    => control_awid,
        s_axi_control_bid     => control_bid,
        s_axi_control_arvalid => s_axi_arvalid,
        s_axi_control_arready => s_axi_arready,
        s_axi_control_araddr  => control_araddr,
        s_axi_control_rvalid  => s_axi_rvalid,
        s_axi_control_rready  => s_axi_rready,
        s_axi_control_rdata   => control_rdata,
        s_axi_control_rresp   => s_axi_rresp,
        s_axi_control_arid    => control_arid,
        s_axi_control_rid     => control_rid,

        -- AXI-4 Master memory (with ID mapping)
        m_axi_gmem_awid    => m_axi_gmem_awid_internal,
        m_axi_gmem_bid     => m_axi_bid,
        m_axi_gmem_awvalid => m_axi_awvalid,
        m_axi_gmem_awready => m_axi_awready,
        m_axi_gmem_awaddr  => m_axi_awaddr,
        m_axi_gmem_awlen   => m_axi_awlen,
        m_axi_gmem_awsize  => m_axi_awsize,
        m_axi_gmem_awburst => m_axi_awburst,
        m_axi_gmem_wvalid  => m_axi_wvalid,
        m_axi_gmem_wready  => m_axi_wready,
        m_axi_gmem_wdata   => m_axi_wdata,
        m_axi_gmem_wstrb   => m_axi_wstrb,
        m_axi_gmem_wlast   => m_axi_wlast,
        m_axi_gmem_bvalid  => m_axi_bvalid,
        m_axi_gmem_bready  => m_axi_bready,
        m_axi_gmem_bresp   => m_axi_bresp,
        m_axi_gmem_arid    => m_axi_gmem_arid_internal,
        m_axi_gmem_rid     => m_axi_rid,
        m_axi_gmem_arvalid => m_axi_arvalid,
        m_axi_gmem_arready => m_axi_arready,
        m_axi_gmem_araddr  => m_axi_araddr,
        m_axi_gmem_arlen   => m_axi_arlen,
        m_axi_gmem_arsize  => m_axi_arsize,
        m_axi_gmem_arburst => m_axi_arburst,
        m_axi_gmem_rvalid  => m_axi_rvalid,
        m_axi_gmem_rready  => m_axi_rready,
        m_axi_gmem_rdata   => m_axi_rdata,
        m_axi_gmem_rlast   => m_axi_rlast,
        m_axi_gmem_rresp   => m_axi_rresp
      );
        
end Accelerator_Top_a;

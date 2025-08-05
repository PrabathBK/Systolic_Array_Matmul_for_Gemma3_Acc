library ieee;
  use ieee.std_logic_1164.all;

-- This entity declaration must match what Top.vhd expects. It should not be changed.

entity accelerator_top is
  port (
    s_axi_aclk    : in    std_logic;
    s_axi_aresetn : in    std_logic;
    -- Master AXI Interface (to DDR Memory)
    m_axi_awvalid : out   std_logic;
    m_axi_awid    : out   std_logic_vector(11 downto 0);
    m_axi_awlen   : out   std_logic_vector(7 downto 0);
    m_axi_awsize  : out   std_logic_vector(2 downto 0);
    m_axi_awburst : out   std_logic_vector(1 downto 0);
    m_axi_awlock  : out   std_logic_vector(0 downto 0);
    m_axi_awcache : out   std_logic_vector(3 downto 0);
    m_axi_awqos   : out   std_logic_vector(3 downto 0);
    m_axi_awaddr  : out   std_logic_vector(63 downto 0);
    m_axi_awprot  : out   std_logic_vector(2 downto 0);
    m_axi_awready : in    std_logic;
    m_axi_wvalid  : out   std_logic;
    m_axi_wlast   : out   std_logic;
    m_axi_wdata   : out   std_logic_vector(127 downto 0);
    m_axi_wstrb   : out   std_logic_vector(15 downto 0);
    m_axi_wready  : in    std_logic;
    m_axi_bready  : out   std_logic;
    m_axi_bvalid  : in    std_logic;
    m_axi_bid     : in    std_logic_vector(11 downto 0);
    m_axi_bresp   : in    std_logic_vector(1 downto 0);
    m_axi_arvalid : out   std_logic;
    m_axi_arid    : out   std_logic_vector(11 downto 0);
    m_axi_arlen   : out   std_logic_vector(7 downto 0);
    m_axi_arsize  : out   std_logic_vector(2 downto 0);
    m_axi_arburst : out   std_logic_vector(1 downto 0);
    m_axi_arlock  : out   std_logic_vector(0 downto 0);
    m_axi_arcache : out   std_logic_vector(3 downto 0);
    m_axi_arqos   : out   std_logic_vector(3 downto 0);
    m_axi_araddr  : out   std_logic_vector(63 downto 0);
    m_axi_arprot  : out   std_logic_vector(2 downto 0);
    m_axi_arready : in    std_logic;
    m_axi_rready  : out   std_logic;
    m_axi_rvalid  : in    std_logic;
    m_axi_rid     : in    std_logic_vector(11 downto 0);
    m_axi_rlast   : in    std_logic;
    m_axi_rresp   : in    std_logic_vector(1 downto 0);
    m_axi_rdata   : in    std_logic_vector(127 downto 0);
    -- Slave AXI-Lite Interface (from CPU)
    s_axi_awid    : in    std_logic_vector(11  downto 0);
    s_axi_awaddr  : in    std_logic_vector(63  downto 0);
    s_axi_awlen   : in    std_logic_vector(7   downto 0);
    s_axi_awsize  : in    std_logic_vector(2   downto 0);
    s_axi_awburst : in    std_logic_vector(1   downto 0);
    s_axi_awlock  : in    std_logic;
    s_axi_awcache : in    std_logic_vector(3   downto 0);
    s_axi_awprot  : in    std_logic_vector(2   downto 0);
    s_axi_awqos   : in    std_logic_vector(3   downto 0);
    s_axi_awvalid : in    std_logic;
    s_axi_awready : out   std_logic;
    s_axi_wdata   : in    std_logic_vector(127 downto 0);
    s_axi_wstrb   : in    std_logic_vector(15  downto 0);
    s_axi_wlast   : in    std_logic;
    s_axi_wvalid  : in    std_logic;
    s_axi_wready  : out   std_logic;
    s_axi_bready  : in    std_logic;
    s_axi_bid     : out   std_logic_vector(11  downto 0);
    s_axi_bresp   : out   std_logic_vector(1   downto 0);
    s_axi_bvalid  : out   std_logic;
    s_axi_arid    : in    std_logic_vector(11  downto 0);
    s_axi_araddr  : in    std_logic_vector(63  downto 0);
    s_axi_arlen   : in    std_logic_vector(7    downto 0);
    s_axi_arsize  : in    std_logic_vector(2    downto 0);
    s_axi_arburst : in    std_logic_vector(1    downto 0);
    s_axi_arlock  : in    std_logic;
    s_axi_arcache : in    std_logic_vector(3    downto 0);
    s_axi_arprot  : in    std_logic_vector(2    downto 0);
    s_axi_arqos   : in    std_logic_vector(3    downto 0);
    s_axi_arvalid : in    std_logic;
    s_axi_arready : out   std_logic;
    s_axi_rready  : in    std_logic;
    s_axi_rid     : out   std_logic_vector(11  downto 0);
    s_axi_rdata   : out   std_logic_vector(127 downto 0);
    s_axi_rresp   : out   std_logic_vector(1   downto 0);
    s_axi_rlast   : out   std_logic;
    s_axi_rvalid  : out   std_logic
  );
end entity accelerator_top;

architecture accelerator_top_a of accelerator_top is

  -- CORRECTED: This component declaration now exactly matches the port list of gemma_accelerator.v
  component gemma_accelerator is
    port (
      ap_clk                : in    std_logic;
      ap_rst_n              : in    std_logic;
      s_axi_control_awvalid : in    std_logic;
      s_axi_control_awready : out   std_logic;
      s_axi_control_awaddr  : in    std_logic_vector(5 downto 0);
      s_axi_control_wvalid  : in    std_logic;
      s_axi_control_wready  : out   std_logic;
      s_axi_control_wdata   : in    std_logic_vector(31 downto 0);
      s_axi_control_wstrb   : in    std_logic_vector(3 downto 0);
      s_axi_control_bvalid  : out   std_logic;
      s_axi_control_bready  : in    std_logic;
      s_axi_control_bresp   : out   std_logic_vector(1 downto 0);
      s_axi_control_arvalid : in    std_logic;
      s_axi_control_arready : out   std_logic;
      s_axi_control_araddr  : in    std_logic_vector(5 downto 0);
      s_axi_control_rvalid  : out   std_logic;
      s_axi_control_rready  : in    std_logic;
      s_axi_control_rdata   : out   std_logic_vector(31 downto 0);
      s_axi_control_rresp   : out   std_logic_vector(1 downto 0);
      m_axi_gmem_awvalid    : out   std_logic;
      m_axi_gmem_awready    : in    std_logic;
      m_axi_gmem_awaddr     : out   std_logic_vector(63 downto 0);
      m_axi_gmem_awlen      : out   std_logic_vector(7 downto 0);
      m_axi_gmem_awsize     : out   std_logic_vector(2 downto 0);
      m_axi_gmem_awburst    : out   std_logic_vector(1 downto 0);
      m_axi_gmem_wvalid     : out   std_logic;
      m_axi_gmem_wready     : in    std_logic;
      m_axi_gmem_wdata      : out   std_logic_vector(127 downto 0);
      m_axi_gmem_wstrb      : out   std_logic_vector(15 downto 0);
      m_axi_gmem_wlast      : out   std_logic;
      m_axi_gmem_bvalid     : in    std_logic;
      m_axi_gmem_bready     : out   std_logic;
      m_axi_gmem_bresp      : in    std_logic_vector(1 downto 0);
      m_axi_gmem_arvalid    : out   std_logic;
      m_axi_gmem_arready    : in    std_logic;
      m_axi_gmem_araddr     : out   std_logic_vector(63 downto 0);
      m_axi_gmem_arlen      : out   std_logic_vector(7 downto 0);
      m_axi_gmem_arsize     : out   std_logic_vector(2 downto 0);
      m_axi_gmem_arburst    : out   std_logic_vector(1 downto 0);
      m_axi_gmem_rvalid     : in    std_logic;
      m_axi_gmem_rready     : out   std_logic;
      m_axi_gmem_rdata      : in    std_logic_vector(127 downto 0);
      m_axi_gmem_rlast      : in    std_logic;
      m_axi_gmem_rresp      : in    std_logic_vector(1 downto 0)
    );
  end component gemma_accelerator;

  -- Signals for the 128-bit to 32-bit AXI-Lite adaptation
  signal s_control_wdata_internal : std_logic_vector(31 downto 0);
  signal s_control_wstrb_internal : std_logic_vector(3 downto 0);
  signal s_control_rdata_internal : std_logic_vector(31 downto 0);

begin

  -- Logic to adapt the 128-bit AXI-Lite bus from the SoC to the 32-bit control port of our IP.
  s_control_wstrb_internal <= s_axi_wstrb(3 downto 0) when s_axi_awaddr(3 downto 2) = "00" else
                              s_axi_wstrb(7 downto 4) when s_axi_awaddr(3 downto 2) = "01" else
                              s_axi_wstrb(11 downto 8) when s_axi_awaddr(3 downto 2) = "10" else
                              s_axi_wstrb(15 downto 12);
  s_control_wdata_internal <= s_axi_wdata(31 downto 0) when s_axi_awaddr(3 downto 2) = "00" else
                              s_axi_wdata(63 downto 32) when s_axi_awaddr(3 downto 2) = "01" else
                              s_axi_wdata(95 downto 64) when s_axi_awaddr(3 downto 2) = "10" else
                              s_axi_wdata(127 downto 96);
  s_axi_rdata              <= s_control_rdata_internal & s_control_rdata_internal & s_control_rdata_internal & s_control_rdata_internal;
  s_axi_bid                <= s_axi_awid;
  s_axi_rid                <= s_axi_arid;
  s_axi_rlast              <= '1';

  -- CORRECTED: Instantiate gemma_accelerator and map all ports correctly.
  -- All unused master ports from the IP are tied off (left open).
  u_gemma_acc : component gemma_accelerator
    port map (
      ap_clk   => s_axi_aclk,
      ap_rst_n => s_axi_aresetn,
      -- Master Interface
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
      m_axi_gmem_rresp   => m_axi_rresp,
      -- Slave Interface
      s_axi_control_awvalid => s_axi_awvalid,
      s_axi_control_awready => s_axi_awready,
      s_axi_control_awaddr  => s_axi_awaddr(5 downto 0),
      s_axi_control_wvalid  => s_axi_wvalid,
      s_axi_control_wready  => s_axi_wready,
      s_axi_control_wdata   => s_control_wdata_internal,
      s_axi_control_wstrb   => s_control_wstrb_internal,
      s_axi_control_bvalid  => s_axi_bvalid,
      s_axi_control_bready  => s_axi_bready,
      s_axi_control_bresp   => s_axi_bresp,
      s_axi_control_arvalid => s_axi_arvalid,
      s_axi_control_arready => s_axi_arready,
      s_axi_control_araddr  => s_axi_araddr(5 downto 0),
      s_axi_control_rvalid  => s_axi_rvalid,
      s_axi_control_rready  => s_axi_rready,
      s_axi_control_rdata   => s_control_rdata_internal,
      s_axi_control_rresp   => s_axi_rresp
    );

end architecture accelerator_top_a;

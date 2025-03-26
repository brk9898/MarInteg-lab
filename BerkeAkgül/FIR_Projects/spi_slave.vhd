library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;  -- Prefer numeric_std over std_logic_arith

entity spi_slave is
  generic(
    data_length : integer := 16  -- Data length in bits
  );
  port(
    reset_n   : in  std_logic;  -- Asynchronous active-low reset
    sclk      : in  std_logic;  -- SPI clock
    ss_n      : in  std_logic;  -- Slave Select (active low)
    mosi      : in  std_logic;  -- Master-Out-Slave-In
    miso      : out std_logic;  -- Master-In-Slave-Out
    rx_enable : in  std_logic;  -- When '1', latch rxBuffer to rx
    tx        : in  std_logic_vector(data_length-1 downto 0); -- Data to transmit
    rx        : out std_logic_vector(data_length-1 downto 0) := (others => '0'); 
    busy      : out std_logic := '0'  -- Indicates slave is busy (ss_n=0)
  );
end spi_slave;

architecture behavioural of spi_slave is

  --------------------------------------------------------------------------
  -- Internal signals
  --------------------------------------------------------------------------
  signal cpol       : std_logic := '0';  -- Clock polarity mode
  signal cpha       : std_logic := '0';  -- Clock phase mode  
  signal mode       : std_logic;  -- mode = cpol XOR cpha
  signal clk        : std_logic;  -- Internal "SPI" clock (derived from sclk)
  signal bit_counter: std_logic_vector(data_length downto 0); 
  signal rxBuffer   : std_logic_vector(data_length-1 downto 0) := (others => '0');
  signal txBuffer   : std_logic_vector(data_length-1 downto 0) := (others => '0');

begin

  --------------------------------------------------------------------------
  -- Indicate "busy" whenever ss_n is low
  --------------------------------------------------------------------------
  busy <= not ss_n;  

  --------------------------------------------------------------------------
  -- Determine SPI mode from cpol and cpha
  --------------------------------------------------------------------------
  mode <= cpol xor cpha;

  --------------------------------------------------------------------------
  -- Internal SPI clock generation 
  --   - If ss_n=1, force clk='0' to avoid spurious edges.
  --   - Otherwise, if mode='1' then clk = sclk, else clk = not sclk
  --------------------------------------------------------------------------
  process(mode, ss_n, sclk)
  begin
    if ss_n = '1' then
      clk <= '0';
    else
      if mode = '1' then
        clk <= sclk;
      else
        clk <= not sclk;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------------
  -- bit_counter logic:
  --   - Reset (when ss_n=1 or reset_n=0):
  --       * If cpha='0', set bit_counter(1)='1'
  --       * If cpha='1', set bit_counter(0)='1'
  --   - Otherwise, shift left on rising edge of clk
  --------------------------------------------------------------------------
  process(ss_n, clk)
  begin
    if (ss_n = '1' or reset_n = '0') then
      if cpha = '0' then
        bit_counter <= (others => '0');
        bit_counter(1) <= '1';
      else
        bit_counter <= (others => '0');
        bit_counter(0) <= '1';
      end if;
    else
      if rising_edge(clk) then
        bit_counter <= bit_counter(data_length-1 downto 0) & '0';
      end if;
    end if;
  end process;

  --------------------------------------------------------------------------
  -- Main SPI logic (receive and transmit)
  --   - Receives data on MOSI, stores in rxBuffer
  --   - On ss_n=1, user can latch rxBuffer to rx
  --   - Transmits data from txBuffer out on MISO
  --   - When ss_n=1, load txBuffer with "tx"
  --------------------------------------------------------------------------
  process(ss_n, clk, rx_enable, reset_n)
  begin
    ------------------------------------------------------------------------
    -- 1) Receive MOSI bit
    ------------------------------------------------------------------------
    if cpha = '0' then
      -- cpha='0' case
      if reset_n = '0' then
        rxBuffer <= (others => '0');
      elsif (bit_counter /= "00000000000000010" and falling_edge(clk)) then
        -- Example check for a certain bit_counter value (16-bit example)
        rxBuffer <= rxBuffer(data_length-2 downto 0) & mosi;
      end if;
    else
      -- cpha='1' case
      if reset_n = '0' then
        rxBuffer <= (others => '0');
      elsif (bit_counter /= "00000000000000001" and falling_edge(clk)) then
        rxBuffer <= rxBuffer(data_length-2 downto 0) & mosi;
      end if;
    end if;

    ------------------------------------------------------------------------
    -- 2) Output the received data if rx_enable=1 and ss_n=1
    ------------------------------------------------------------------------
    if reset_n = '0' then
      rx <= (others => '0');
    elsif (ss_n = '1' and rx_enable = '1') then
      rx <= rxBuffer;
    end if;

    ------------------------------------------------------------------------
    -- 3) Transmit register loading and shifting
    ------------------------------------------------------------------------
    if reset_n = '0' then
      txBuffer <= (others => '0');
    elsif (ss_n = '1') then
      -- load the next transmit word from "tx"
      txBuffer <= tx;
    elsif (bit_counter(data_length) = '0' and rising_edge(clk)) then
      -- shift out the MSB on each rising_edge(clk)
      txBuffer <= txBuffer(data_length-2 downto 0) & txBuffer(data_length-1);
    end if;

    ------------------------------------------------------------------------
    -- 4) Drive MISO
    --    - High impedance ('Z') when not selected or reset
    --    - Otherwise output MSB of txBuffer
    ------------------------------------------------------------------------
    if (ss_n = '1' or reset_n = '0') then
      miso <= 'Z';
    elsif rising_edge(clk) then
      miso <= txBuffer(data_length-1);
    end if;

  end process;

end behavioural;

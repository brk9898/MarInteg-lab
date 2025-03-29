library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.synchronizer_pkg.all;


entity Top_Module is
  generic(
        c_clkfreq		: integer := 100_000_000;
        c_baudrate		: integer := 1_000_000;  
        DATA_WIDTH      : integer := 16  -- Data length in bits
  );
  Port(
        clk      : in  std_logic;
        reset    : in  std_logic;
        
        rx       : in  std_logic; -- 3-bit switch sinyali                
                
        sclk     : in  std_logic;
        ss_n     : in  std_logic;
        mosi     : in  std_logic;
        miso     : out std_logic;
        
        LED      : out std_logic_vector(15 downto 0)        
   );
end Top_Module;

architecture Behavioral of Top_Module is

component FIR_Filter is
    Generic (
        filter_taps  : integer := 50;
        input_width  : integer range 8 to 25 := 24; 
        coeff_width  : integer range 8 to 18 := 16;
        output_width : integer range 8 to 43 := 43  
    );
    Port ( 
        clk          : in STD_LOGIC;
        reset        : in STD_LOGIC;
        enable       : in STD_LOGIC;
        coeff_s      : in coefficients(0 to filter_taps-1); 
        data_i       : in STD_LOGIC_VECTOR (input_width-1 downto 0);
        data_o       : out STD_LOGIC_VECTOR (output_width-1 downto 0)
    );
end component;

component spi_slave is
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
end component;

component uart_rx is
    generic (
        c_clkfreq		: integer := 100_000_000;
        c_baudrate		: integer := 1_000_000
    );
    port (
        clk				: in std_logic;
        rx_i			: in std_logic;
        dout_o			: out std_logic_vector (7 downto 0);
        rx_done_tick_o	: out std_logic
    );
end component;

signal spi_rx_data          : std_logic_vector(DATA_WIDTH-1 downto 0);
signal spi_rx_data_sync     : std_logic_vector(DATA_WIDTH-1 downto 0);
signal spi_tx_data          : std_logic_vector(DATA_WIDTH-1 downto 0);
signal spi_tx_data_sync     : std_logic_vector(DATA_WIDTH-1 downto 0);
signal spi_busy             : std_logic;    
signal spi_busy_sync        : std_logic;

signal RESET_FIR            : std_logic := '0';
signal ENABLE_FIR           : std_logic := '0';
signal DOUT_RX              : std_logic_vector (15 downto 0) := (others => '0');
signal DOUT_TX              : std_logic_vector (15 downto 0) := (others => '0');

signal UART_REG             : coefficients(0 to 49) := (others => (others => '0'));
signal UART_BUFFER          : coefficients(0 to 49) := (others => (others => '0'));
signal DOUT_UART_RX         : std_logic_vector (7 downto 0) := (others => '0');
signal rx_done_tick         : std_logic := '0';
signal INDEX                : integer := 0;
signal INDEX_1              : integer := 0;
signal rx_sync              : std_logic := '0';
signal rx_1                 : std_logic := '0';


type STATES is (IDLE, SPI_TX_RX_MODE, FIR_PROCESS);
signal MSTATE : STATES := IDLE;

type STATES_2 is (IDLE, UART_RX_MODE, DONE);
signal MSTATE_2 : STATES_2 := IDLE;


begin


process(clk, reset) begin

    if reset = '1' then

        MSTATE          <= IDLE;
        ENABLE_FIR      <= '0';
        RESET_FIR       <= '1';


        MSTATE_2        <= IDLE;
        UART_REG        <= (others => (others => '0'));
        UART_BUFFER     <= (others => (others => '0'));
        INDEX           <= 0;
        INDEX_1         <= 0;

    elsif rising_edge(clk) then

        RESET_FIR       <= '0';
        spi_tx_data     <= DOUT_TX;  
        LED             <= DOUT_TX;
        DOUT_RX         <= spi_rx_data_sync;

        rx_sync         <= rx_1;
        rx_1            <= rx;

        case MSTATE is

            when IDLE =>

                ENABLE_FIR <= '0';

                if(spi_busy_sync = '1') then

                    MSTATE <= SPI_TX_RX_MODE;

                end if;    

            when SPI_TX_RX_MODE =>

                if spi_busy_sync = '0' then

                    MSTATE <= FIR_PROCESS;

                end if;

            when FIR_PROCESS =>

                ENABLE_FIR <= '1';
                MSTATE <= IDLE;  

            when others =>

                MSTATE <= IDLE;

        end case;

        case MSTATE_2 is

            when IDLE =>
        
                if rx_done_tick = '1' then
                    MSTATE_2 <= UART_RX_MODE;
                end if;

            when UART_RX_MODE =>

                if INDEX < 50 then
                    if INDEX_1 = 0 then
                        UART_REG(INDEX)(7 downto 0) <= signed(DOUT_UART_RX);
                        INDEX_1 <= INDEX_1 + 1;
                    else
                        UART_REG(INDEX)(15 downto 8) <= signed(DOUT_UART_RX);
                        INDEX_1 <= 0;
                        INDEX <= INDEX + 1;
                    end if;
                    INDEX <= INDEX + 1;
                    MSTATE_2 <= IDLE;                    
                else
                    MSTATE_2 <= DONE;
                end if;

            when DONE =>

                for i in 0 to 49 loop
                    UART_BUFFER(i) <= UART_REG(i);
                end loop;

                MSTATE_2 <= IDLE;

            when others =>
                MSTATE_2 <= IDLE;

        end case;

    end if;
end process;


SPI_Slave_Inst : entity work.spi_slave
   generic map (
        data_length => DATA_WIDTH
   )
   port map (
        reset_n   => '1',
        sclk      => sclk,
        ss_n      => ss_n,
        mosi      => mosi,
        miso      => miso,
        rx_enable => '1',
        tx        => spi_tx_data_sync,
        rx        => spi_rx_data,
        busy      => spi_busy
   );
       

GEN_SYNC : for i in 0 to DATA_WIDTH-1 generate

    UUT : entity work.async_input_sync
    port map(
        clk => sclk,
        async_in => spi_tx_data(i),
        sync_out => spi_tx_data_sync(i)      
    );

end generate GEN_SYNC;    

GEN_SYNC_1 : for i in 0 to DATA_WIDTH-1 generate

    UUT : entity work.async_input_sync
    port map(
        clk => clk,
        async_in => spi_rx_data(i),
        sync_out => spi_rx_data_sync(i)      
    );
   
end generate GEN_SYNC_1;
 
UUT : entity work.async_input_sync
port map(
     clk => clk,
     async_in => spi_busy,
     sync_out => spi_busy_sync      
);
       
UUT_1 : FIR_Filter
generic map (
       filter_taps  => 50,
       input_width  => DATA_WIDTH,
       coeff_width  => 16,
       output_width => DATA_WIDTH
)
port map(
       clk      => clk,
       reset    => RESET_FIR,
       enable   => ENABLE_FIR,
       coeff_s  => UART_BUFFER,
       data_i   => DOUT_RX,
       data_o   => DOUT_TX
);

UUT_2 : entity work.uart_rx
generic map (
        c_clkfreq		=> c_clkfreq,
        c_baudrate		=> c_baudrate
)
port map (
        clk				=> clk,
        rx_i			=> rx_sync,
        dout_o			=> DOUT_UART_RX,
        rx_done_tick_o	=> rx_done_tick
);

end Behavioral;

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 07.03.2025 21:28:11
-- Design Name: 
-- Module Name: TB_SPI - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity TB_SPI is
--  Port ( );
end TB_SPI;

architecture Behavioral of TB_SPI is

component Top_Module is
    Port(       
        clk      : in  std_logic;
        reset    : in  std_logic;        
        sclk     : in  std_logic;
        rx       : in  std_logic; -- 3-bit switch sinyali                
        ss_n     : in  std_logic;
        mosi     : in  std_logic;
        miso     : out std_logic;
        LED      : out std_logic_vector(15 downto 0)
    );
end component;

signal clk          : std_logic := '0';
signal reset        : std_logic := '0';
signal sclk         : std_logic := '0';
signal ss_n         : std_logic := '1';
signal mosi         : std_logic := '0';
signal miso         : std_logic := '0';
signal cpol         : std_logic := '0';
signal cpha         : std_logic := '0';
signal SPISIGNAL 	: std_logic_vector(15 downto 0) := (others => '0');
signal rx           : std_logic := '0';

constant c_baud115200	: time := 1 us;
constant c_hex43		: std_logic_vector (9 downto 0) := '1' & x"43" & '0';
constant c_hexA5		: std_logic_vector (9 downto 0) := '1' & x"A5" & '0';

begin

-- Clock process definitions
clk_i_process :process
begin
	clk <= '0';
	wait for 5 ns;
	clk <= '1';
	wait for 5 ns;
end process;


-- Clock process definitions
sclk_i_process :process
begin
	sclk <= '0';
	wait for 528 ns;
	sclk <= '1';
	wait for 528 ns;
end process;

P_STIMULI : process begin

    wait for 50 ns;
    
    for i in 0 to 9 loop
        rx <= c_hex43(i);
        wait for c_baud115200;
    end loop;
    
    wait for 10 us;
    
    for i in 0 to 9 loop
        rx <= c_hexA5(i);
        wait for c_baud115200;
    end loop; 
    
    wait for 20 us;

end process P_STIMULI;


SPIWRITE_P : process begin
    
    wait for 10 us;
    wait until falling_edge(sclk);

	ss_n <= '0';
 
	-- for cpol = 1 cpha = 1
	-- for cpol = 0 cpha = 0
    
    wait until falling_edge(sclk);
    mosi <= SPISIGNAL(15);
	wait until falling_edge(sclk);
	mosi <= SPISIGNAL(14);
	wait until falling_edge(sclk);
	mosi <= SPISIGNAL(13);
	wait until falling_edge(sclk);
	mosi <= SPISIGNAL(12);
	wait until falling_edge(sclk);
	mosi <= SPISIGNAL(11);
	wait until falling_edge(sclk);
	mosi <= SPISIGNAL(10);
	wait until falling_edge(sclk);
	mosi <= SPISIGNAL(9);
	wait until falling_edge(sclk);
	mosi <= SPISIGNAL(8);
    wait until falling_edge(sclk);
    mosi <= SPISIGNAL(7);
	wait until falling_edge(sclk);
	mosi <= SPISIGNAL(6);
	wait until falling_edge(sclk);
	mosi <= SPISIGNAL(5);
	wait until falling_edge(sclk);
	mosi <= SPISIGNAL(4);
	wait until falling_edge(sclk);
	mosi <= SPISIGNAL(3);
	wait until falling_edge(sclk);
	mosi <= SPISIGNAL(2);
	wait until falling_edge(sclk);
	mosi <= SPISIGNAL(1);
	wait until falling_edge(sclk);
	mosi <= SPISIGNAL(0);
    wait until falling_edge(sclk);
    

	ss_n <= '1';
   
    wait for 500 ns;
    wait until falling_edge(sclk);
    SPISIGNAL <= x"0001";

end process;



-- Instantiate the Unit Under Test (UUT)
uut: Top_Module 
PORT MAP (
        clk       =>    clk      ,
        reset     =>    reset    ,
        rx        =>    rx       ,
        sclk      =>    sclk     ,
        ss_n      =>    ss_n     ,
        mosi      =>    mosi     ,
        miso      =>    miso     ,
        LED   =>    open
);

end Behavioral;

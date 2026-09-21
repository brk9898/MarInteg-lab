library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
entity GW_Top is
    generic (
        IMG_WIDTH  : integer := 256;
        IMG_HEIGHT : integer := 256
    );
    Port (
        clk         : in  std_logic;
        reset       : in  std_logic;
        R_i         : in  std_logic_vector(7 downto 0);
        G_i         : in  std_logic_vector(7 downto 0);
        B_i         : in  std_logic_vector(7 downto 0);
        pixel_valid : in  std_logic;
        frame_done  : in  std_logic;
        R_out       : out std_logic_vector(7 downto 0);
        G_out       : out std_logic_vector(7 downto 0);
        B_out       : out std_logic_vector(7 downto 0)
    );
end GW_Top;
architecture Structural of GW_Top is
    signal R_avg, G_avg, B_avg  : std_logic_vector(7 downto 0);
    signal Gray_avg_o_wire      : std_logic_vector(9 downto 0);
    signal Gray_avg             : unsigned(9 downto 0);
    
    signal averages_ready       : std_logic := '0';
    signal stage2_pixel_valid   : std_logic := '0';
    
    component GW_Stage_1
        generic (
            IMG_WIDTH  : integer := 256;
            IMG_HEIGHT : integer := 256
        );
        Port (
            clk         : in  std_logic;
            reset       : in  std_logic;
            R_i         : in  std_logic_vector(7 downto 0);
            G_i         : in  std_logic_vector(7 downto 0);
            B_i         : in  std_logic_vector(7 downto 0);
            pixel_valid : in  std_logic;
            frame_done  : in  std_logic;
            R_avg_o     : out std_logic_vector(7 downto 0);
            G_avg_o     : out std_logic_vector(7 downto 0);
            B_avg_o     : out std_logic_vector(7 downto 0);
            Gray_avg_o  : out std_logic_vector(9 downto 0)
        );
    end component;
    component GW_Stage_2
        generic (
            IMG_WIDTH  : integer := 256;
            IMG_HEIGHT : integer := 256
        );
        Port (
            clk         : in  std_logic;
            reset       : in  std_logic;
            R_i         : in  std_logic_vector(7 downto 0);
            G_i         : in  std_logic_vector(7 downto 0);
            B_i         : in  std_logic_vector(7 downto 0);
            pixel_valid : in  std_logic;
            R_avg1      : in  std_logic_vector(7 downto 0);
            G_avg1      : in  std_logic_vector(7 downto 0);
            B_avg1      : in  std_logic_vector(7 downto 0);
            Gray_avg    : in  unsigned(9 downto 0);
            R_out       : out std_logic_vector(7 downto 0);
            G_out       : out std_logic_vector(7 downto 0);
            B_out       : out std_logic_vector(7 downto 0)
        );
    end component;
begin
    U1: GW_Stage_1
        port map (
            clk => clk,
            reset => reset,
            R_i => R_i,
            G_i => G_i,
            B_i => B_i,
            pixel_valid => pixel_valid,
            frame_done => frame_done,
            R_avg_o => R_avg,
            G_avg_o => G_avg,
            B_avg_o => B_avg,
            Gray_avg_o => Gray_avg_o_wire
        );
        Gray_avg <= unsigned(Gray_avg_o_wire);
    U2: GW_Stage_2
        port map (
            clk => clk,
            reset => reset,
            R_i => R_i,
            G_i => G_i,
            B_i => B_i,
            pixel_valid => stage2_pixel_valid,
            R_avg1 => R_avg,
            G_avg1 => G_avg,
            B_avg1 => B_avg,
            Gray_avg => Gray_avg,
            R_out => R_out,
            G_out => G_out,
            B_out => B_out
        );
        
        
    kontrol_process: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                averages_ready <= '0';
            else
                if frame_done = '1' then
                    averages_ready <= '1';
                end if;
            end if;
        end if;
    end process;
    
    stage2_pixel_valid <= pixel_valid or averages_ready;
end Structural;
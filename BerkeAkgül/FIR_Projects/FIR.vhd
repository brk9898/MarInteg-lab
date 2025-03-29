library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.synchronizer_pkg.all;


entity FIR_Filter is
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
end FIR_Filter;

architecture Behavioral of FIR_Filter is

attribute use_dsp : string;
attribute use_dsp of Behavioral : architecture is "yes";

constant mac_width : integer := coeff_width+input_width;

type input_registers is array(0 to filter_taps-1) of signed(input_width-1 downto 0);
signal areg_s  : input_registers := (others=>(others=>'0'));

type coeff_registers is array(0 to filter_taps-1) of signed(coeff_width-1 downto 0);
signal breg_s : coeff_registers := (others=>(others=>'0'));

type mult_registers is array(0 to filter_taps-1) of signed(input_width+coeff_width-1 downto 0);
signal mreg_s : mult_registers := (others=>(others=>'0'));

type dsp_registers is array(0 to filter_taps-1) of signed(mac_width-1 downto 0);
signal preg_s : dsp_registers := (others=>(others=>'0'));



begin  

Coeff_Array: for i in 0 to filter_taps-1 generate
    Coeff: for n in 0 to coeff_width-1 generate
        Coeff_Sign: if n > coeff_width-2 generate
            breg_s(i)(n) <= coeff_s(i)(coeff_width-1);
        end generate;
        Coeff_Value: if n < coeff_width-1 generate
            breg_s(i)(n) <= coeff_s(i)(n);
        end generate;
    end generate;
end generate;

data_o <= std_logic_vector(preg_s(0)(mac_width-2 downto mac_width-output_width-1));         
      
process(clk)
begin
    if rising_edge(clk) then
        if (reset = '1') then
            for i in 0 to filter_taps-1 loop
                areg_s(i) <= (others=> '0');
                mreg_s(i) <= (others=> '0');
                preg_s(i) <= (others=> '0');
            end loop;
        elsif (reset = '0') then
            if(enable = '1') then         
                for i in 0 to filter_taps-1 loop
                    areg_s(i) <= signed(data_i);
                    if (i < filter_taps-1) then
                        mreg_s(i) <= areg_s(i) * breg_s(i);
                        preg_s(i) <= mreg_s(i) + preg_s(i+1);
                    else
                        mreg_s(i) <= areg_s(i) * breg_s(i);
                        preg_s(i) <= mreg_s(i);
                    end if;
                end loop; 
            end if;    
        end if;
    end if;
end process;

end Behavioral;

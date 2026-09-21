

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity GW_Stage_2 is
    generic (
        IMG_WIDTH  : integer := 256;
        IMG_HEIGHT : integer := 256
    );
    port (
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
end GW_Stage_2;

architecture Behavioral of GW_Stage_2 is
type InvLUT_Type is array (0 to 255) of std_logic_vector(15 downto 0);

constant InvLUT : InvLUT_Type := (
       x"0000", x"FFFF", x"8000", x"5555", x"4000", x"3333", x"2AAB", x"2492",
    x"2000", x"1C72", x"199A", x"1746", x"1555", x"13B1", x"1249", x"1111",
    x"1000", x"0F0F", x"0E39", x"0D79", x"0CCD", x"0C31", x"0BA3", x"0B21",
    x"0AAB", x"0A3D", x"09D9", x"097B", x"0925", x"08D4", x"0889", x"0842",
    x"0800", x"07C2", x"0787", x"0750", x"071C", x"06EB", x"06BD", x"0691",
    x"0667", x"063E", x"0618", x"05F4", x"05D1", x"05B0", x"0591", x"0572",
    x"0555", x"0539", x"051F", x"0505", x"04EC", x"04D5", x"04BE", x"04A8",
    x"0492", x"047E", x"046A", x"0457", x"0444", x"0432", x"0421", x"0410",
    x"0400", x"03F0", x"03E1", x"03D2", x"03C4", x"03B6", x"03A8", x"039B",
    x"038E", x"0382", x"0376", x"036A", x"035E", x"0353", x"0348", x"033E",
    x"0333", x"0329", x"031F", x"0316", x"030C", x"0303", x"02FA", x"02F1",
    x"02E9", x"02E0", x"02D8", x"02D0", x"02C8", x"02C1", x"02B9", x"02B2",
    x"02AB", x"02A4", x"029D", x"0296", x"028F", x"0289", x"0283", x"027C",
    x"0276", x"0270", x"026A", x"0264", x"025F", x"0259", x"0254", x"024E",
    x"0249", x"0244", x"023F", x"023A", x"0235", x"0230", x"022B", x"0227",
    x"0222", x"021E", x"021A", x"0215", x"0211", x"020C", x"0208", x"0204",
    x"0200", x"01FC", x"01F8", x"01F4", x"01F0", x"01ED", x"01E9", x"01E5",
    x"01E2", x"01DE", x"01DB", x"01D7", x"01D4", x"01D1", x"01CE", x"01CA",
    x"01C7", x"01C4", x"01C1", x"01BE", x"01BB", x"01B8", x"01B5", x"01B2",
    x"01AF", x"01AC", x"01AA", x"01A7", x"01A4", x"01A1", x"019F", x"019C",
    x"019A", x"0197", x"0195", x"0192", x"0190", x"018D", x"018B", x"0188",
    x"0186", x"0184", x"0182", x"017F", x"017D", x"017B", x"0179", x"0176",
    x"0174", x"0172", x"0170", x"016E", x"016C", x"016A", x"0168", x"0166",
    x"0164", x"0162", x"0160", x"015E", x"015D", x"015B", x"0159", x"0157",
    x"0155", x"0154", x"0152", x"0150", x"014E", x"014D", x"014B", x"0149",
    x"0148", x"0146", x"0144", x"0143", x"0141", x"0140", x"013E", x"013D",
    x"013B", x"013A", x"0138", x"0137", x"0135", x"0134", x"0132", x"0131",
    x"012F", x"012E", x"012D", x"012B", x"012A", x"0129", x"0127", x"0126",
    x"0125", x"0123", x"0122", x"0121", x"011F", x"011E", x"011D", x"011C",
    x"011A", x"0119", x"0118", x"0117", x"0116", x"0115", x"0113", x"0112",
    x"0111", x"0110", x"010F", x"010E", x"010D", x"010B", x"010A", x"0109",
    x"0108", x"0107", x"0106", x"0105", x"0104", x"0103", x"0102", x"0101"
);
    
    signal stage1_valid : std_logic := '0';
    signal stage2_valid : std_logic := '0';
    
    signal gain_R : std_logic_vector(15 downto 0) := (others => '0');
    signal gain_G : std_logic_vector(15 downto 0) := (others => '0');
    signal gain_B : std_logic_vector(15 downto 0) := (others => '0');
    signal R_i_reg, G_i_reg, B_i_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal Gray_avg_reg : unsigned(9 downto 0) := (others => '0');
    
    signal temp_R, temp_G, temp_B : unsigned(23 downto 0) := (others => '0');
    signal Gray_avg_reg2 : unsigned(9 downto 0) := (others => '0');
    signal R_bal, G_bal, B_bal : unsigned(33 downto 0) := (others => '0');

begin

process(clk)
begin
    if rising_edge(clk) then
        if reset = '1' then
            stage1_valid <= '0';
            stage2_valid <= '0';
            gain_R <= (others => '0');
            gain_G <= (others => '0');
            gain_B <= (others => '0');
            R_i_reg <= (others => '0');
            G_i_reg <= (others => '0');
            B_i_reg <= (others => '0');
            Gray_avg_reg <= (others => '0');
            temp_R <= (others => '0');
            temp_G <= (others => '0');
            temp_B <= (others => '0');
            Gray_avg_reg2 <= (others => '0');
            R_bal <= (others => '0');
            G_bal <= (others => '0');
            B_bal <= (others => '0');
            R_out <= (others => '0');
            G_out <= (others => '0');
            B_out <= (others => '0');
        else
            stage1_valid <= pixel_valid;
            stage2_valid <= stage1_valid;
            
            if pixel_valid = '1' then
                gain_R <= InvLUT(to_integer(unsigned(R_avg1)));
                gain_G <= InvLUT(to_integer(unsigned(G_avg1)));
                gain_B <= InvLUT(to_integer(unsigned(B_avg1)));
                R_i_reg <= R_i;
                G_i_reg <= G_i;
                B_i_reg <= B_i;
                Gray_avg_reg <= Gray_avg;
            end if;
            
            if stage1_valid = '1' then
                temp_R <= (unsigned(R_i_reg) * unsigned(gain_R));
                temp_G <= (unsigned(G_i_reg) * unsigned(gain_G));
                temp_B <= (unsigned(B_i_reg) * unsigned(gain_B));
                Gray_avg_reg2 <= Gray_avg_reg;
            end if;
            
            if stage2_valid = '1' then
                R_bal <= temp_R * Gray_avg_reg2;
                G_bal <= temp_G * Gray_avg_reg2;
                B_bal <= temp_B * Gray_avg_reg2;
                

                if R_bal(33 downto 24) /= 0 then
                    R_out <= x"FF"; 
                else
                    R_out <= std_logic_vector(R_bal(23 downto 16));
                end if;
                
                if G_bal(33 downto 24) /= 0 then
                    G_out <= x"FF"; 
                else
                    G_out <= std_logic_vector(G_bal(23 downto 16));
                end if;
                
                if B_bal(33 downto 24) /= 0 then
                    B_out <= x"FF"; 
                else
                    B_out <= std_logic_vector(B_bal(23 downto 16));
                end if;
            end if;
        end if;
    end if;
end process;

end Behavioral;
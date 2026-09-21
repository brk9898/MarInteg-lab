library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- =============================================================
--  OV7670 Register ROM
--  - Basit ve "güvenli" init sırası (önce reset, sonra format)
--  - RGB444 enable: 0x8C = 0x02  (bit1=1 enable, bit0=0 xRGB)
--  - COM15: full-range + RGB444/RGB565 seçimi burada önemlidir
--  - NOT: COM7 soft reset sonrası sensörün toparlaması için genelde
--         bir miktar bekleme gerekir (I2C master tarafında delay).
-- =============================================================
entity ov7670_registers is
  port(
    clk     : in  std_logic;
    resend  : in  std_logic;
    advance : in  std_logic;
    reg_out : out std_logic_vector(15 downto 0);
    fin     : out std_logic
  );
end entity;

architecture rtl of ov7670_registers is

  type t_rom is array(natural range <>) of std_logic_vector(15 downto 0);

  -- reg_out[15:8] = reg_addr, reg_out[7:0] = data
  constant C_ROM : t_rom := (
    ----------------------------------------------------------------
    -- 0) Soft reset (COM7[7]=1)
    ----------------------------------------------------------------
    x"1280",  -- COM7 = 0x80 : SCCB reset
    x"1280",  -- tekrar (bazı modüllerde daha stabil oluyor)

    ----------------------------------------------------------------
    -- 1) Clock prescaler
    ----------------------------------------------------------------
    x"1100",  -- CLKRC = 0x00 : prescaler /1 (XCLK'e bağlı)

    ----------------------------------------------------------------
    -- 2) Output format: RGB + VGA
    -- COM7: bit[2]=RGB select, bit[5:3]=size (VGA/QVGA/...)
    -- 0x04 => RGB + VGA (klasik ayar)
    ----------------------------------------------------------------
    --x"1200",  -- COM7 = 0x04 : RGB mode + VGA

    ----------------------------------------------------------------
    -- 3) RGB444 enable (datasheet: RGB444 reg 0x8C)
    -- 0x02: enable=1 (bit1), xRGB=0 (bit0)
    -- SENDE 0x03 vardı; o bit0=1 yapar, byte packing'i değiştirebilir.
    ----------------------------------------------------------------
    --x"8C02",  -- RGB444 = 0x02 : RGB444 enable, xRGB

    ----------------------------------------------------------------
    -- 4) COM15 (0x40): output range + RGB format control
    -- 0xC0: full range (00..FF). RGB444 için yaygın kullanılan ayar.
    -- Not: Bazı kaynaklarda RGB565 için 0xD0 görülür.
    ----------------------------------------------------------------
    --x"40C0",  -- COM15 = 0xC0 : full range

    ----------------------------------------------------------------
    -- DONE
    ----------------------------------------------------------------
    x"FFFF"
  );

  constant C_ROM_LEN : integer := C_ROM'length;

  signal addr : integer range 0 to C_ROM_LEN - 1 := 0;
  signal sreg : std_logic_vector(15 downto 0) := (others => '1');

begin

  fin     <= '1' when sreg = x"FFFF" else '0';
  reg_out <= sreg;

  p_reg : process(clk)
  begin
    if rising_edge(clk) then
      if resend = '1' then
        addr <= 0;
      elsif advance = '1' then
        if addr < C_ROM_LEN - 1 then
          addr <= addr + 1;
        end if;
      end if;

      -- 1 clock gecikmeli ROM çıkışı
      sreg <= C_ROM(addr);
    end if;
  end process;

end architecture;
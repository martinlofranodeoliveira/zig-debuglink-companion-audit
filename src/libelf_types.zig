pub const Elf = anyopaque;
pub const Elf_Scn = anyopaque;
pub const Elf_Type = c_uint;

pub const ELF_C_READ: c_uint = 1;
pub const EV_CURRENT: c_uint = 1;

pub const EI_MAG0: usize = 0;
pub const EI_MAG1: usize = 1;
pub const EI_MAG2: usize = 2;
pub const EI_MAG3: usize = 3;
pub const EI_CLASS: usize = 4;
pub const EI_DATA: usize = 5;
pub const EI_VERSION: usize = 6;

pub const ELFCLASSNONE: u8 = 0;
pub const ELFCLASS32: u8 = 1;
pub const ELFCLASS64: u8 = 2;

pub const ELFDATANONE: u8 = 0;
pub const ELFDATA2LSB: u8 = 1; // Little-endian
pub const ELFDATA2MSB: u8 = 2; // Big-endian

pub const SHT_PROGBITS: u32 = 1;
pub const SHT_NOTE: u32 = 7;
pub const SHT_NOBITS: u32 = 8;

pub const NT_GNU_BUILD_ID: u32 = 3;

pub const GElf_Ehdr = extern struct {
    e_ident: [16]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u64,
    e_phoff: u64,
    e_shoff: u64,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

pub const GElf_Shdr = extern struct {
    sh_name: u32,
    sh_type: u32,
    sh_flags: u64,
    sh_addr: u64,
    sh_offset: u64,
    sh_size: u64,
    sh_link: u32,
    sh_info: u32,
    sh_addralign: u64,
    sh_entsize: u64,
};

pub const Elf_Data = extern struct {
    d_buf: ?*anyopaque,
    d_type: Elf_Type,
    d_version: c_uint,
    d_size: usize,
    d_off: i64,
    d_align: usize,
};

pub const Stat = extern struct {
    st_dev: u64,
    st_ino: u64,
    st_nlink: u64,
    st_mode: u32,
    st_uid: u32,
    st_gid: u32,
    __pad0: u32,
    st_rdev: u64,
    st_size: i64,
    st_blksize: i64,
    st_blocks: i64,
    st_atime: i64,
    st_atime_nsec: i64,
    st_mtime: i64,
    st_mtime_nsec: i64,
    st_ctime: i64,
    st_ctime_nsec: i64,
    __unused: [3]i64,
};

pub const S_IFMT: u32 = 0o170000;
pub const S_IFREG: u32 = 0o100000;
pub const S_IFLNK: u32 = 0o120000;
pub const S_IFDIR: u32 = 0o040000;

pub const O_RDONLY: c_int = 0;

pub extern "c" fn elf_version(version: c_uint) c_uint;
pub extern "c" fn elf_begin(fildes: c_int, cmd: c_uint, ref: ?*Elf) ?*Elf;
pub extern "c" fn elf_end(elf: ?*Elf) c_int;
pub extern "c" fn elf_nextscn(elf: ?*Elf, scn: ?*Elf_Scn) ?*Elf_Scn;
pub extern "c" fn elf_strptr(elf: ?*Elf, section: usize, offset: usize) ?[*:0]const u8;
pub extern "c" fn elf_getdata(scn: ?*Elf_Scn, data: ?*Elf_Data) ?*Elf_Data;
pub extern "c" fn gelf_getehdr(elf: ?*Elf, dst: *GElf_Ehdr) ?*GElf_Ehdr;
pub extern "c" fn gelf_getshdr(scn: ?*Elf_Scn, dst: *GElf_Shdr) ?*GElf_Shdr;

pub extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
pub extern "c" fn close(fd: c_int) c_int;
pub extern "c" fn read(fd: c_int, buf: [*]u8, count: usize) isize;
pub extern "c" fn write(fd: c_int, buf: [*]const u8, count: usize) isize;
pub extern "c" fn lseek(fd: c_int, offset: i64, whence: c_int) i64;
pub extern "c" fn fstat(fd: c_int, buf: *Stat) c_int;
pub extern "c" fn lstat(path: [*:0]const u8, buf: *Stat) c_int;
pub extern "c" fn unlink(path: [*:0]const u8) c_int;
pub extern "c" fn symlink(target: [*:0]const u8, linkpath: [*:0]const u8) c_int;
pub extern "c" fn mkdir(path: [*:0]const u8, mode: u32) c_int;

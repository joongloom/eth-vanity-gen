# cy_worker.pyx
# cython: language_level=3

import time
import json
import os
import traceback
from eth_account import Account
from mnemonic import Mnemonic
from colorama import Fore, Style


from coincurve import PublicKey
from eth_utils import to_checksum_address, keccak

cdef dict CONFIG = {
    "RESULT_FILE": "results.txt",
    "LOG_FILE": "log.log",
}

cdef bint is_beautiful_optimized(str address, str pref, str suff):
    cdef str addr_clean = address[2:].lower()
    
    if pref is not None:
        if addr_clean.startswith(pref):
            return True
            
    if suff is not None:
        if address.lower().endswith(suff):
            return True

    # Раскомментируй return False ниже, если хочешь искать ТОЛЬКО свои префиксы.
    # if pref or suff: return False

    if addr_clean[:8] == addr_clean[0] * 8:
        return True
    
    if addr_clean[-8:] == addr_clean[-1] * 8:
        return True

    if addr_clean.endswith("0000000"):
        return True

    cdef int count = 1
    cdef str prev = ''
    cdef str char
    
    for char in addr_clean:
        if char == prev:
            count += 1
            if count >= 8: return True
        else:
            count = 1
            prev = char
            
    return False

cdef tuple fast_generate():
    cdef bytes private_key_bytes = os.urandom(32)
    # coincurve работает быстрее eth_keys
    cdef object public_key = PublicKey.from_secret(private_key_bytes).format(compressed=False)[1:]
    cdef object addr = keccak(public_key)[-20:]
    return to_checksum_address(addr), private_key_bytes.hex()

def cython_worker(total_gen, total_found, active_workers, lock, args):
    cdef object mnemo = Mnemonic("english")
    cdef str address
    cdef str private_key_hex
    cdef str words
    cdef bint is_fast = args.fastmode
    
    cdef str arg_pref = args.fp.lower() if args.fp else None
    cdef str arg_suff = args.fs.lower() if args.fs else None
    cdef bint arg_console = args.console
    cdef bint arg_notext = args.notext
    cdef str arg_json = args.json
    
    cdef int local_counter = 0
    cdef int BATCH_SIZE = 2000 

    try:
        while True:
            if is_fast:
                address, private_key_hex = fast_generate()
                words = "N/A (Fast Mode)"
            else:
                words = mnemo.generate(strength=256)
                seed = mnemo.to_seed(words, passphrase="")
                account = Account.from_key(seed[:32])
                address = account.address
                private_key_hex = account.key.hex()

            if is_beautiful_optimized(address, arg_pref, arg_suff):
                print(f"\n{Fore.GREEN}[+] FOUND: {address}{Style.RESET_ALL}")
                
                with lock:
                    if not arg_notext:
                        with open(CONFIG["RESULT_FILE"], "a") as f:
                            f.write(f"Address: {address}\nKey: {private_key_hex}\nSeed: {words}\n\n")
                    
                    if arg_json:
                        res_data = {
                            "address": address,
                            "private_key": private_key_hex,
                            "seed": words,
                            "timestamp": time.time()
                        }
                        with open(arg_json, "a") as jf:
                            jf.write(json.dumps(res_data) + "\n")
                            
                    total_found.value += 1
            
            else:
                if arg_console:
                    print(f"{Fore.RED}{address}{Style.RESET_ALL} is bad")
                
                local_counter += 1
                if local_counter >= BATCH_SIZE:
                    with lock:
                        total_gen.value += local_counter
                    local_counter = 0
                    
    except Exception:
        print(Fore.RED + "Worker Error:")
        traceback.print_exc()
    finally:
        with lock:
            active_workers.value -= 1
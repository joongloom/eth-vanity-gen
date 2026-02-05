import multiprocessing
import time
import logging
import argparse
from colorama import init, Fore, Style

try:
    import cy_worker
except ImportError:
    print(Fore.RED + "модуль cy_worker не найден.")
    print("запустите команду компиляции: python setup.py build_ext --inplace")
    exit()

CONFIG = {
    "LOG_FILE": "log.log",
    "UPDATE_INTERVAL": 20
}

init(autoreset=True)

logging.basicConfig(
    filename=CONFIG["LOG_FILE"],
    level=logging.INFO,
    format='%(asctime)s %(message)s',
    datefmt='%Y/%m/%d %H:%M:%S'
)

def monitor_process(start_time, total_gen, total_found, active_workers):
    while active_workers.value > 0:
        time.sleep(CONFIG["UPDATE_INTERVAL"])
        elapsed = time.time() - start_time
        speed = total_gen.value / elapsed if elapsed > 0 else 0
        status = f"Gen: {total_gen.value} | Found: {total_found.value} | Speed: {speed:.2f} addr/s | Workers: {active_workers.value}"
        logging.info(status)
        print(f"{Fore.CYAN}[STATUS]{Style.RESET_ALL} {status}", end="\r")

def start_app():
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--console", action="store_true")
    parser.add_argument("-t", "--threads", type=int, default=multiprocessing.cpu_count())
    parser.add_argument("--fp", type=str)
    parser.add_argument("--fs", type=str)
    parser.add_argument("--fm", "--fastmode", action="store_true", dest="fastmode")
    parser.add_argument("-j", "--json", type=str)
    parser.add_argument("--nt", "--no-text", action="store_true", dest="notext")
    args = parser.parse_args()

    start_time = time.time()
    total_gen = multiprocessing.Value('i', 0)
    total_found = multiprocessing.Value('i', 0)
    active_workers = multiprocessing.Value('i', args.threads)
    lock = multiprocessing.Lock()
    
    processes = []
    mode_str = "FAST" if args.fastmode else "STANDARD"
    print(f"{Fore.YELLOW}Starting {args.threads} workers in {mode_str} mode (Cython Optimized)...{Style.RESET_ALL}")
    
    target_func = cy_worker.cython_worker

    for _ in range(args.threads):
        p = multiprocessing.Process(target=target_func, args=(total_gen, total_found, active_workers, lock, args))
        p.start()
        processes.append(p)
        
    mon = multiprocessing.Process(target=monitor_process, args=(start_time, total_gen, total_found, active_workers))
    mon.daemon = True
    mon.start()
    
    try:
        for p in processes:
            p.join()
    except KeyboardInterrupt:
        for p in processes: p.terminate()
            
    final_stats = f"\nFinal: Gen: {total_gen.value} | Found: {total_found.value} | Time: {time.time() - start_time:.2f}s"
    logging.info(final_stats)
    print(final_stats)

if __name__ == '__main__':
    start_app()
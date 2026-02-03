"""
Finetune GPT-2 for a specific speaker's speech patterns.
This script takes a speaker name, loads their specific train/test CSV files from the same directory,
and finetunes 'openai-community/gpt2' using Causal Language Modeling (CLM).
"""

import os
import sys
import argparse
import torch

# Increase timeout for Hugging Face Hub downloads
os.environ["HF_HUB_READ_TIMEOUT"] = "300"
os.environ["HF_HUB_CONNECT_TIMEOUT"] = "300"

from datasets import load_dataset
from transformers import (
    AutoTokenizer,
    AutoModelForCausalLM,
    DataCollatorForLanguageModeling,
    TrainingArguments,
    Trainer
)

def finetune_for_speaker(speaker_name, epochs=3, batch_size=4, output_dir=None):
    """
    Finetunes the model for a given speaker.
    """
    # Format speaker name for file matching (e.g., "Justin Trudeau" -> "Justin_Trudeau")
    speaker_file_name = speaker_name.replace(" ", "_")
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    train_file = os.path.join(script_dir, f"{speaker_file_name}_train.csv")
    test_file = os.path.join(script_dir, f"{speaker_file_name}_test.csv")
    
    if not os.path.exists(train_file):
        print(f"Error: Train file not found at {train_file}")
        # List available speakers to help the user
        csv_files = [f for f in os.listdir(script_dir) if f.endswith("_train.csv")]
        available_speakers = [f.replace("_train.csv", "").replace("_", " ") for f in csv_files]
        if available_speakers:
            print(f"Available speakers: {', '.join(available_speakers)}")
        return

    if not output_dir:
        output_dir = os.path.join(script_dir, f"gpt2_{speaker_file_name}")

    print(f"Finetuning for: {speaker_name}")
    print(f"Loading data from: {train_file}")
    
    # Load dataset from CSV
    print("Loading dataset...")
    dataset = load_dataset("csv", data_files={"train": train_file, "test": test_file} if os.path.exists(test_file) else {"train": train_file})
    
    model_checkpoint = "openai-community/gpt2"
    print(f"Loading tokenizer and model from {model_checkpoint}...")
    tokenizer = AutoTokenizer.from_pretrained(model_checkpoint)
    
    # GPT-2 does not have a padding token by default
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
        
    model = AutoModelForCausalLM.from_pretrained(model_checkpoint)
    print("Model and tokenizer loaded.")

    # Preprocessing: Tokenize the text
    def tokenize_function(examples):
        return tokenizer(examples["text"])

    tokenized_datasets = dataset.map(
        tokenize_function, 
        batched=True, 
        num_proc=4, 
        remove_columns=["text", "label"]
    )

    # Chunking: Group texts into blocks of fixed length
    block_size = 128

    def group_texts(examples):
        concatenated_examples = {k: sum(examples[k], []) for k in examples.keys()}
        total_length = len(concatenated_examples[list(examples.keys())[0]])
        if total_length >= block_size:
            total_length = (total_length // block_size) * block_size
        result = {
            k: [t[i : i + block_size] for i in range(0, total_length, block_size)]
            for k, t in concatenated_examples.items()
        }
        # For Causal LM, the labels are the same as the inputs
        result["labels"] = result["input_ids"].copy()
        return result

    lm_datasets = tokenized_datasets.map(
        group_texts,
        batched=True,
        num_proc=4,
    )

    # Data collator for CLM
    data_collator = DataCollatorForLanguageModeling(
        tokenizer=tokenizer, 
        mlm=False
    )

    # Training configuration
    training_args = TrainingArguments(
        output_dir=output_dir,
        eval_strategy="epoch" if "test" in lm_datasets else "no",
        learning_rate=5e-5, # Slightly higher LR for GPT-2 often helps
        weight_decay=0.01,
        num_train_epochs=epochs,
        per_device_train_batch_size=batch_size,
        per_device_eval_batch_size=batch_size,
        save_strategy="epoch",
        logging_dir=os.path.join(output_dir, "logs"),
        report_to="none",
    )

    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=lm_datasets["train"],
        eval_dataset=lm_datasets["test"] if "test" in lm_datasets else None,
        data_collator=data_collator,
    )

    trainer.train()
    
    # Save the final model and tokenizer
    trainer.save_model(output_dir)
    tokenizer.save_pretrained(output_dir)
    print(f"Model saved to {output_dir}")

def generate_sample(model_path, prompt="Mr. Speaker,"):
    print(f"\nGenerating sample with prompt: {prompt}")
    tokenizer = AutoTokenizer.from_pretrained(model_path)
    model = AutoModelForCausalLM.from_pretrained(model_path)
    
    device = "cuda" if torch.cuda.is_available() else "mps" if torch.backends.mps.is_available() else "cpu"
    model.to(device)
    
    inputs = tokenizer(prompt, return_tensors="pt").to(device)
    
    with torch.no_grad():
        output_tokens = model.generate(
            **inputs, 
            max_length=100, 
            num_return_sequences=1,
            no_repeat_ngram_size=2,
            do_sample=True,
            top_k=50,
            top_p=0.95,
            temperature=0.7
        )
    
    print(f"Result:\n{tokenizer.decode(output_tokens[0], skip_special_tokens=True)}")

def main():
    parser = argparse.ArgumentParser(description="Finetune GPT-2 for a specific speaker.")
    parser.add_argument("--speaker", type=str, required=True, help="Name of the speaker (e.g., 'Justin Trudeau')")
    parser.add_argument("--epochs", type=int, default=3, help="Number of training epochs")
    parser.add_argument("--batch_size", type=int, default=4, help="Training batch size")
    parser.add_argument("--output_dir", type=str, default=None, help="Output directory for the model")
    parser.add_argument("--generate", action="store_true", help="Generate a sample after training")

    args = parser.parse_args()
    
    speaker_file_name = args.speaker.replace(" ", "_")
    output_dir = args.output_dir or os.path.join(os.path.dirname(os.path.abspath(__file__)), f"gpt2_{speaker_file_name}")

    finetune_for_speaker(
        speaker_name=args.speaker,
        epochs=args.epochs,
        batch_size=args.batch_size,
        output_dir=output_dir
    )

    if args.generate:
        generate_sample(output_dir)

if __name__ == "__main__":
    main()
